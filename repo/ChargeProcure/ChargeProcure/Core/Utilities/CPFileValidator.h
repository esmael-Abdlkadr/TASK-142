#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CPFileType) {
    CPFileTypePDF,
    CPFileTypeJPEG,
    CPFileTypePNG,
    CPFileTypeUnknown,
};

@interface CPFileValidator : NSObject

/// Detect file type from magic bytes.
+ (CPFileType)detectTypeFromData:(NSData *)data;

/// Returns YES if file type is allowed (PDF/JPEG/PNG).
+ (BOOL)isAllowedType:(CPFileType)type;

/// Returns mime type string for file type.
+ (NSString *)mimeTypeForFileType:(CPFileType)type;

/// Returns file extension for file type.
+ (NSString *)extensionForFileType:(CPFileType)type;

/// Validates data: checks magic header and size <= 25MB. Returns YES if valid.
+ (BOOL)validateData:(NSData *)data error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
