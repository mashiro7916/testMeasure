//
//  OpenCVWrapper.h
//  testMeasure
//
//  OpenCV wrapper for Swift
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Line segment structure for Swift
@interface LineSegment : NSObject
@property (nonatomic, assign) float x1;
@property (nonatomic, assign) float y1;
@property (nonatomic, assign) float x2;
@property (nonatomic, assign) float y2;
@end

@interface OpenCVWrapper : NSObject

// Convert RGB image to grayscale using OpenCV
+ (UIImage *)convertToGrayscale:(UIImage *)image;

// Detect line segments using LSD algorithm
+ (NSArray<LineSegment *> *)detectLines:(UIImage *)image;

// Draw line segments on image
+ (UIImage *)drawLines:(UIImage *)image lines:(NSArray<LineSegment *> *)lines selectedIndex:(NSInteger)selectedIndex;

// Get OpenCV version
+ (NSString *)openCVVersion;

@end

NS_ASSUME_NONNULL_END
