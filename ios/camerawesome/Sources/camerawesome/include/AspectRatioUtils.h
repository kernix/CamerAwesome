//
//  AspectRatioUtils.h
//  camerawesome
//
//  Created by Dimitri Dessus on 29/03/2023.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "AspectRatio.h"

NS_ASSUME_NONNULL_BEGIN

@interface AspectRatioUtils : NSObject

+ (AspectRatio)convertAspectRatio:(NSString *)aspectRatioStr;
+ (CGFloat)landscapeAspectRatioValue:(AspectRatio)ratio;
+ (CGSize)croppedLandscapeSizeForAspectRatio:(AspectRatio)ratio sourceSize:(CGSize)sourceSize;
+ (CGRect)centerCropRectForBufferSize:(CGSize)bufferSize aspectRatio:(AspectRatio)ratio;
/// Matches biclic preview framing: top bar only masks the stream, bottom is the
/// natural end of the 16:9 preview (not a symmetric center crop).
+ (CGRect)previewAlignedCropRectForBufferSize:(CGSize)bufferSize aspectRatio:(AspectRatio)ratio;

@end

NS_ASSUME_NONNULL_END
