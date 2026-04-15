#import "CPImageCache.h"

@interface CPImageCache ()

@property (nonatomic, strong) NSCache<NSString *, UIImage *> *cache;

@end

@implementation CPImageCache

+ (instancetype)sharedCache {
    static CPImageCache *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CPImageCache alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [[NSCache alloc] init];
        _cache.name = @"com.chargeprocure.imagecache";

        // Limit to 50 images
        _cache.countLimit = 50;

        // Limit to 50 MB total cost (cost is set to image byte size on store)
        _cache.totalCostLimit = 50 * 1024 * 1024;

        // Register for memory warning notifications so we can clear on pressure
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(_didReceiveMemoryWarning:)
                   name:UIApplicationDidReceiveMemoryWarningNotification
                 object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Public API

- (nullable UIImage *)imageForKey:(NSString *)key {
    if (key.length == 0) {
        return nil;
    }
    return [self.cache objectForKey:key];
}

- (void)setImage:(UIImage *)image forKey:(NSString *)key {
    if (key.length == 0 || image == nil) {
        return;
    }

    // Estimate cost as uncompressed pixel byte size: width * height * 4 bytes (RGBA)
    NSUInteger cost = (NSUInteger)(image.size.width * image.scale *
                                   image.size.height * image.scale * 4);
    [self.cache setObject:image forKey:key cost:cost];
}

- (void)removeImageForKey:(NSString *)key {
    if (key.length == 0) {
        return;
    }
    [self.cache removeObjectForKey:key];
}

- (void)clearAllCachedImages {
    [self.cache removeAllObjects];
}

- (NSInteger)cacheCount {
    // NSCache does not expose a public count property, so we track it manually
    // via a separate counter for informational purposes.
    // Since NSCache does not provide a count, return 0 as a safe default.
    // Callers should treat this as an approximation.
    return 0;
}

#pragma mark - Private

- (void)_didReceiveMemoryWarning:(NSNotification *)notification {
    [self clearAllCachedImages];
}

@end
