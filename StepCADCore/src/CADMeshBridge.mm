// Conversion signal -> exception d'OCCT (SIGSEGV/SIGBUS/SIGFPE/SIGILL -> Standard_Failure) : sur Unix,
// OCC_CONVERT_SIGNALS doit être défini avant les headers OCCT pour activer OCC_CATCH_SIGNALS (setjmp).
#ifndef OCC_CONVERT_SIGNALS
#define OCC_CONVERT_SIGNALS
#endif

#import "CADMeshBridge.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#include <STEPControl_Reader.hxx>
#include <TopoDS_Shape.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <TopExp_Explorer.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Face.hxx>
#include <BRep_Tool.hxx>
#include <Poly_Triangulation.hxx>
#include <BRepBndLib.hxx>
#include <Bnd_Box.hxx>
#include <Standard_ErrorHandler.hxx>
#include <Standard_Failure.hxx>
#include <OSD.hxx>

#pragma clang diagnostic pop

#include <vector>
#include <cmath>
#include <algorithm>
#include <limits>

static NSError *StepViewError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"com.stepview.error"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation CADMeshData

- (instancetype)initWithVertices:(NSData *)vertices
                         normals:(NSData *)normals
                         indices:(NSData *)indices
                     vertexCount:(NSUInteger)vertexCount
                   triangleCount:(NSUInteger)triangleCount
                            bMin:(simd_float3)bMin
                            bMax:(simd_float3)bMax {
    self = [super init];
    if (self) {
        _vertexData = vertices;
        _normalData = normals;
        _indexData = indices;
        _vertexCount = vertexCount;
        _triangleCount = triangleCount;
        _boundingBoxMin = bMin;
        _boundingBoxMax = bMax;
        _dimensions = bMax - bMin;
    }
    return self;
}

@end

static CADMeshData *LoadStepMesh(NSURL *fileURL, double linearDeflection, NSUInteger maxTriangles,
                                 NSError * __strong *outError) {
    // Active une seule fois la conversion des signaux fatals en exceptions OCCT (process-wide).
    // FPE désactivés (Standard_False) : seuls les accès mémoire invalides / instructions illégales sont convertis.
    static dispatch_once_t signalOnce;
    dispatch_once(&signalOnce, ^{ OSD::SetSignal(Standard_False); });

    @autoreleasepool {
        if (!fileURL || !fileURL.isFileURL) {
            if (outError) {
                *outError = [NSError errorWithDomain:@"com.stepview.error"
                                                code:1000
                                            userInfo:@{NSLocalizedDescriptionKey: @"URL de fichier invalide."}];
            }
            return nil;
        }

        const char *filePath = fileURL.path.fileSystemRepresentation;
        if (!filePath) {
            if (outError) {
                *outError = [NSError errorWithDomain:@"com.stepview.error"
                                                code:1000
                                            userInfo:@{NSLocalizedDescriptionKey: @"Chemin de fichier invalide."}];
            }
            return nil;
        }

        try {
            OCC_CATCH_SIGNALS  // setjmp : un signal fatal dans OCCT (même thread) est relancé en Standard_Failure

            // 1. Lecture du fichier STEP
            STEPControl_Reader reader;
            IFSelect_ReturnStatus status = reader.ReadFile(filePath);
            if (status != IFSelect_RetDone) {
                if (outError) {
                    *outError = [NSError errorWithDomain:@"com.stepview.error"
                                                    code:1001
                                                userInfo:@{NSLocalizedDescriptionKey: @"Échec de lecture du fichier STEP (format non reconnu ou fichier corrompu)."}];
                }
                return nil;
            }

            // 2. Transfert géométrique vers TopoDS_Shape
            reader.TransferRoots();
            TopoDS_Shape shape = reader.OneShape();
            if (shape.IsNull()) {
                if (outError) {
                    *outError = [NSError errorWithDomain:@"com.stepview.error"
                                                    code:1002
                                                userInfo:@{NSLocalizedDescriptionKey: @"Aucune géométrie ou solide 3D détecté dans le fichier."}];
                }
                return nil;
            }

            // 3. Calcul de la Bounding Box
            Bnd_Box bndBox;
            BRepBndLib::Add(shape, bndBox);
            Standard_Real xMin = 0, yMin = 0, zMin = 0, xMax = 0, yMax = 0, zMax = 0;
            bndBox.Get(xMin, yMin, zMin, xMax, yMax, zMax);

            simd_float3 minBounds = simd_make_float3((float)xMin, (float)yMin, (float)zMin);
            simd_float3 maxBounds = simd_make_float3((float)xMax, (float)yMax, (float)zMax);
            float diagonal = simd_distance(minBounds, maxBounds);

            // 4. Tessellation adaptative (LOD automatique pour préserver la RAM)
            double deflection = linearDeflection;
            if (deflection < 0.0) {
                // Valeur négative : fraction de la diagonale (ex. -0.005 = 0.5%), utile pour un LOD plus grossier
                deflection = std::max(static_cast<double>(diagonal) * -deflection, 0.0005);
            } else if (deflection == 0.0) {
                // Règle ergonomique : 0.2% de la diagonale, avec garde-fous
                deflection = std::max(static_cast<double>(diagonal * 0.002f), 0.0005);
            }

            // Tessellation BRep avec angle de 0.5 rad (~28 deg) pour compromis vitesse/qualité
            BRepMesh_IncrementalMesh mesher(shape, deflection, Standard_False, 0.5, Standard_True);
            mesher.Perform();

            std::vector<simd_float3> allVertices;
            std::vector<simd_float3> allNormals;
            std::vector<uint32_t> allIndices;

            uint64_t vertexOffset = 0;
            uint64_t totalTriangles = 0;

            // 5. Extraction de toutes les faces B-Rep
            for (TopExp_Explorer faceExp(shape, TopAbs_FACE); faceExp.More(); faceExp.Next()) {
                TopoDS_Face face = TopoDS::Face(faceExp.Current());
                TopLoc_Location location;
                Handle(Poly_Triangulation) triangulation = BRep_Tool::Triangulation(face, location);

                if (triangulation.IsNull()) {
                    continue;
                }

                const gp_Trsf &transform = location.Transformation();
                Standard_Integer nbNodes = triangulation->NbNodes();
                Standard_Integer nbTriangles = triangulation->NbTriangles();

                if (nbNodes == 0 || nbTriangles == 0) {
                    continue;
                }

                // Garde-fous : plafond de triangles (mémoire) et indices 32 bits
                totalTriangles += static_cast<uint64_t>(nbTriangles);
                if (maxTriangles > 0 && totalTriangles > maxTriangles) {
                    if (outError) {
                        *outError = StepViewError(1006, [NSString stringWithFormat:
                            @"Modèle trop complexe (plus de %lu triangles) pour cet aperçu. Ouvrez-le dans StepView.",
                            (unsigned long)maxTriangles]);
                    }
                    return nil;
                }
                if (vertexOffset + static_cast<uint64_t>(nbNodes) > std::numeric_limits<uint32_t>::max()) {
                    if (outError) {
                        *outError = StepViewError(1007, @"Modèle trop volumineux : nombre de sommets supérieur à la limite (2^32).");
                    }
                    return nil;
                }

                bool isReversed = (face.Orientation() == TopAbs_REVERSED);

                // Extraction des sommets dans le repère global
                std::vector<simd_float3> faceVertices;
                faceVertices.reserve(nbNodes);
                for (Standard_Integer i = 1; i <= nbNodes; ++i) {
                    gp_Pnt p = triangulation->Node(i).Transformed(transform);
                    faceVertices.push_back(simd_make_float3((float)p.X(), (float)p.Y(), (float)p.Z()));
                }

                // Normales : utiliser les normales natives ou les calculer
                std::vector<simd_float3> faceNormals(nbNodes, simd_make_float3(0, 0, 0));
                bool hasNativeNormals = triangulation->HasNormals();

                if (hasNativeNormals) {
                    for (Standard_Integer i = 1; i <= nbNodes; ++i) {
                        gp_Dir n = triangulation->Normal(i).Transformed(transform);
                        if (isReversed) {
                            n.Reverse();
                        }
                        faceNormals[i - 1] = simd_make_float3((float)n.X(), (float)n.Y(), (float)n.Z());
                    }
                }

                // Extraction des indices de triangles (conversion 1-based -> 0-based)
                std::vector<uint32_t> faceIndices;
                faceIndices.reserve(nbTriangles * 3);

                for (Standard_Integer i = 1; i <= nbTriangles; ++i) {
                    Standard_Integer n1, n2, n3;
                    triangulation->Triangle(i).Get(n1, n2, n3);

                    uint32_t idx1 = static_cast<uint32_t>(n1 - 1);
                    uint32_t idx2 = static_cast<uint32_t>(n2 - 1);
                    uint32_t idx3 = static_cast<uint32_t>(n3 - 1);

                    if (isReversed) {
                        std::swap(idx2, idx3);
                    }

                    faceIndices.push_back(idx1);
                    faceIndices.push_back(idx2);
                    faceIndices.push_back(idx3);

                    // Si pas de normales natives, accumuler les normales de facette
                    if (!hasNativeNormals) {
                        simd_float3 v1 = faceVertices[idx1];
                        simd_float3 v2 = faceVertices[idx2];
                        simd_float3 v3 = faceVertices[idx3];
                        simd_float3 e1 = v2 - v1;
                        simd_float3 e2 = v3 - v1;
                        simd_float3 fn = simd_cross(e1, e2);
                        faceNormals[idx1] += fn;
                        faceNormals[idx2] += fn;
                        faceNormals[idx3] += fn;
                    }
                }

                // Normalisation des normales calculées
                if (!hasNativeNormals) {
                    for (auto &norm : faceNormals) {
                        float len = simd_length(norm);
                        if (len > 1e-6f) {
                            norm = norm / len;
                        } else {
                            norm = simd_make_float3(0.0f, 1.0f, 0.0f);
                        }
                    }
                }

                // Intégration dans le maillage global avec offset
                for (auto idx : faceIndices) {
                    allIndices.push_back(static_cast<uint32_t>(vertexOffset) + idx);
                }
                allVertices.insert(allVertices.end(), faceVertices.begin(), faceVertices.end());
                allNormals.insert(allNormals.end(), faceNormals.begin(), faceNormals.end());

                vertexOffset += static_cast<uint64_t>(nbNodes);
            }

            // Libération de la mémoire OCCT
            reader.ClearShapes();
            Standard::Purge();

            if (allIndices.empty() || allVertices.empty()) {
                if (outError) {
                    *outError = [NSError errorWithDomain:@"com.stepview.error"
                                                    code:1003
                                                userInfo:@{NSLocalizedDescriptionKey: @"La tessellation n'a produit aucun polygone."}];
                }
                return nil;
            }

            NSData *vertexData = [NSData dataWithBytes:allVertices.data()
                                                length:allVertices.size() * sizeof(simd_float3)];
            NSData *normalData = [NSData dataWithBytes:allNormals.data()
                                                length:allNormals.size() * sizeof(simd_float3)];
            NSData *indexData = [NSData dataWithBytes:allIndices.data()
                                               length:allIndices.size() * sizeof(uint32_t)];

            return [[CADMeshData alloc] initWithVertices:vertexData
                                                 normals:normalData
                                                 indices:indexData
                                             vertexCount:allVertices.size()
                                           triangleCount:allIndices.size() / 3
                                                    bMin:minBounds
                                                    bMax:maxBounds];

        } catch (const Standard_Failure &failure) {
            const char *msg = failure.GetMessageString();
            NSString *desc = msg ? [NSString stringWithUTF8String:msg] : @"Erreur interne Open CASCADE";
            if (outError) {
                *outError = [NSError errorWithDomain:@"com.stepview.error"
                                                code:1004
                                            userInfo:@{NSLocalizedDescriptionKey: desc}];
            }
            return nil;
        } catch (...) {
            if (outError) {
                *outError = [NSError errorWithDomain:@"com.stepview.error"
                                                code:1005
                                            userInfo:@{NSLocalizedDescriptionKey: @"Erreur critique non gérée lors de la lecture STEP."}];
            }
            return nil;
        }
    }
}

@implementation CADMeshBridge

+ (nullable CADMeshData *)loadStepMeshFromURL:(NSURL *)fileURL
                            linearDeflection:(double)linearDeflection
                                       error:(NSError * _Nullable * _Nullable)outError {
    // Comportement historique : déflexion <= 0 = adaptative par défaut, pas de plafond de triangles.
    return [self loadStepMeshFromURL:fileURL
                    linearDeflection:std::max(linearDeflection, 0.0)
                        maxTriangles:0
                               error:outError];
}

+ (nullable CADMeshData *)loadStepMeshFromURL:(NSURL *)fileURL
                            linearDeflection:(double)linearDeflection
                                maxTriangles:(NSUInteger)maxTriangles
                                       error:(NSError * _Nullable * _Nullable)outError {
    // L'erreur est écrite hors de l'@autoreleasepool de LoadStepMesh : sinon l'NSError autoreleased
    // serait libéré à la sortie du pool et l'appelant lirait un pointeur invalide.
    NSError *strongError = nil;
    CADMeshData *result = LoadStepMesh(fileURL, linearDeflection, maxTriangles, &strongError);
    if (!result && outError) {
        *outError = strongError;
    }
    return result;
}

@end
