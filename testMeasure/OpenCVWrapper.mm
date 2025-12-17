//
//  OpenCVWrapper.mm
//  testMeasure
//
//  OpenCV wrapper implementation
//

#import "OpenCVWrapper.h"

#ifdef __cplusplus
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#pragma clang diagnostic ignored "-Wunused-parameter"

// OpenCV 4.12 for iOS
// Make sure opencv2.framework is added to the project and Framework Search Paths is set
#import <opencv2/opencv.hpp>
#import <opencv2/imgcodecs/ios.h>

#pragma clang diagnostic pop
#endif

@implementation LineSegment
@end

@implementation OpenCVWrapper

+ (UIImage *)convertToGrayscale:(UIImage *)image {
    // Convert UIImage to cv::Mat
    cv::Mat colorMat;
    UIImageToMat(image, colorMat);
    
    // Convert to grayscale
    cv::Mat grayMat;
    cv::cvtColor(colorMat, grayMat, cv::COLOR_BGR2GRAY);
    
    // Convert back to UIImage
    UIImage *grayImage = MatToUIImage(grayMat);
    
    return grayImage;
}

+ (NSArray<LineSegment *> *)detectLines:(UIImage *)image {
    NSMutableArray<LineSegment *> *result = [NSMutableArray array];
    
    // Convert UIImage to cv::Mat
    cv::Mat colorMat;
    UIImageToMat(image, colorMat);
    
    // Convert to grayscale
    cv::Mat grayMat;
    if (colorMat.channels() > 1) {
        cv::cvtColor(colorMat, grayMat, cv::COLOR_BGR2GRAY);
    } else {
        grayMat = colorMat;
    }
    
    // Create LSD detector
    cv::Ptr<cv::LineSegmentDetector> lsd = cv::createLineSegmentDetector(cv::LSD_REFINE_STD);
    
    // Detect lines
    std::vector<cv::Vec4f> lines;
    lsd->detect(grayMat, lines);
    
    // Filter lines by minimum length (e.g., 50 pixels)
    float minLength = 50.0f;
    
    for (const auto& line : lines) {
        float x1 = line[0];
        float y1 = line[1];
        float x2 = line[2];
        float y2 = line[3];
        
        // Calculate line length
        float length = sqrtf((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
        
        if (length >= minLength) {
            LineSegment *segment = [[LineSegment alloc] init];
            segment.x1 = x1;
            segment.y1 = y1;
            segment.x2 = x2;
            segment.y2 = y2;
            [result addObject:segment];
        }
    }
    
    NSLog(@"DEBUG: LSD detected %lu lines (filtered from %lu)", (unsigned long)result.count, (unsigned long)lines.size());
    
    return result;
}

+ (UIImage *)drawLines:(UIImage *)image lines:(NSArray<LineSegment *> *)lines selectedIndex:(NSInteger)selectedIndex {
    // Convert UIImage to cv::Mat
    cv::Mat colorMat;
    UIImageToMat(image, colorMat);
    
    // Ensure we have a color image
    if (colorMat.channels() == 1) {
        cv::cvtColor(colorMat, colorMat, cv::COLOR_GRAY2BGR);
    } else if (colorMat.channels() == 4) {
        cv::cvtColor(colorMat, colorMat, cv::COLOR_RGBA2BGR);
    }
    
    // Draw all lines
    for (NSInteger i = 0; i < lines.count; i++) {
        LineSegment *line = lines[i];
        cv::Point pt1((int)line.x1, (int)line.y1);
        cv::Point pt2((int)line.x2, (int)line.y2);
        
        if (i == selectedIndex) {
            // Selected line: thick green
            cv::line(colorMat, pt1, pt2, cv::Scalar(0, 255, 0), 4);
            // Draw endpoints
            cv::circle(colorMat, pt1, 8, cv::Scalar(0, 0, 255), -1);
            cv::circle(colorMat, pt2, 8, cv::Scalar(0, 0, 255), -1);
        } else {
            // Other lines: thin blue
            cv::line(colorMat, pt1, pt2, cv::Scalar(255, 100, 100), 2);
        }
    }
    
    // Convert back to UIImage
    cv::cvtColor(colorMat, colorMat, cv::COLOR_BGR2RGB);
    UIImage *resultImage = MatToUIImage(colorMat);
    
    return resultImage;
}

+ (NSString *)openCVVersion {
    return [NSString stringWithFormat:@"%s", CV_VERSION];
}

@end
