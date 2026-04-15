#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CPImageCache : NSObject

+ (instancetype)sharedCache;

/// Load image from cache or disk. Returns nil if not found.
- (nullable UIImage *)imageForKey:(NSString *)key;

/// Store image in cache. key is typically file path or attachment UUID.
- (void)setImage:(UIImage *)image forKey:(NSString *)key;

/// Remove image from cache.
- (void)removeImageForKey:(NSString *)key;

/// Clear all cached images (called on memory warning).
- (void)clearAllCachedImages;

/// Current cache count.
- (NSInteger)cacheCount;

@end

NS_ASSUME_NONNULL_END
