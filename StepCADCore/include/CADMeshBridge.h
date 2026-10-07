#import <Foundation/Foundation.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

@interface CADMeshData : NSObject

@property (nonatomic, readonly) NSData *vertexData;   // Array of simd_float3
@property (nonatomic, readonly) NSData *normalData;   // Array of simd_float3
@property (nonatomic, readonly) NSData *indexData;    // Array of uint32_t
@property (nonatomic, readonly) NSUInteger vertexCount;
@property (nonatomic, readonly) NSUInteger triangleCount;
@property (nonatomic, readonly) simd_float3 boundingBoxMin;
@property (nonatomic, readonly) simd_float3 boundingBoxMax;
@property (nonatomic, readonly) simd_float3 dimensions;

- (instancetype)initWithVertices:(NSData *)vertices
                         normals:(NSData *)normals
                         indices:(NSData *)indices
                     vertexCount:(NSUInteger)vertexCount
                   triangleCount:(NSUInteger)triangleCount
                            bMin:(simd_float3)bMin
                            bMax:(simd_float3)bMax;

@end

@interface CADMeshBridge : NSObject

/// Loads and tessellates a STEP/STP file.
/// If linearDeflection <= 0, an adaptive deflection based on the bounding box diagonal will be used.
+ (nullable CADMeshData *)loadStepMeshFromURL:(NSURL *)fileURL
                            linearDeflection:(double)linearDeflection
                                       error:(NSError * _Nullable * _Nullable)outError;

@end

NS_ASSUME_NONNULL_END
