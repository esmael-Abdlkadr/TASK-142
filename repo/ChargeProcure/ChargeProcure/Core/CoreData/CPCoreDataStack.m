#import "CPCoreDataStack.h"

@interface CPCoreDataStack ()

@property (nonatomic, readwrite, strong) NSPersistentContainer *persistentContainer;
@property (nonatomic, readwrite, strong) NSManagedObjectContext *mainContext;

@end

@implementation CPCoreDataStack

#pragma mark - Singleton

+ (instancetype)sharedStack {
    static CPCoreDataStack *_sharedStack = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedStack = [[CPCoreDataStack alloc] init];
    });
    return _sharedStack;
}

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupPersistentContainer];
    }
    return self;
}

- (void)setupPersistentContainer {
    _persistentContainer = [[NSPersistentContainer alloc] initWithName:@"Model"];

    // When the app is launched under XCUITest (UI_TESTING=1), use an in-memory
    // store so every launch starts with a clean, deterministic state and store
    // loads synchronously (no disk I/O, no migration).
    BOOL isUITesting = [[[NSProcessInfo processInfo] environment][@"UI_TESTING"]
                        isEqualToString:@"1"];

    NSPersistentStoreDescription *storeDescription = _persistentContainer.persistentStoreDescriptions.firstObject;
    if (storeDescription) {
        if (isUITesting) {
            storeDescription.type = NSInMemoryStoreType;
            storeDescription.URL  = [NSURL URLWithString:@"memory://ChargeProcureUITest"];
        } else {
            // Enable lightweight automatic migration
            storeDescription.shouldMigrateStoreAutomatically = YES;
            storeDescription.shouldInferMappingModelAutomatically = YES;
            storeDescription.type = NSSQLiteStoreType;
        }
    }

    __weak typeof(self) weakSelf = self;
    [_persistentContainer loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *description, NSError *error) {
        if (error) {
            // Attempt recovery: delete and recreate the store on unresolvable migration failure
            NSLog(@"[CPCoreDataStack] Failed to load persistent store: %@\nUserInfo: %@", error.localizedDescription, error.userInfo);
            [weakSelf handleStoreLoadError:error forDescription:description];
            return;
        }
        NSLog(@"[CPCoreDataStack] Persistent store loaded: %@", description.URL.lastPathComponent);
        [weakSelf configureMainContext];
    }];
}

- (void)handleStoreLoadError:(NSError *)error forDescription:(NSPersistentStoreDescription *)description {
    // For unrecoverable migration errors, remove the old store and reload
    if (description.URL) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray<NSString *> *extensions = @[@"", @"-wal", @"-shm"];
        for (NSString *ext in extensions) {
            NSString *path = [description.URL.path stringByAppendingString:ext];
            if ([fm fileExistsAtPath:path]) {
                NSError *removeError = nil;
                [fm removeItemAtPath:path error:&removeError];
                if (removeError) {
                    NSLog(@"[CPCoreDataStack] Failed to remove store file at %@: %@", path, removeError.localizedDescription);
                }
            }
        }

        [self.persistentContainer loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *desc, NSError *retryError) {
            if (retryError) {
                NSLog(@"[CPCoreDataStack] Fatal: Could not recover persistent store after removal: %@", retryError.localizedDescription);
                // In production, this is a fatal unrecoverable error.
                // Consider crashing with a user-facing message rather than undefined behavior.
                abort();
            }
            NSLog(@"[CPCoreDataStack] Persistent store recreated successfully.");
            [self configureMainContext];
        }];
    } else {
        NSLog(@"[CPCoreDataStack] Fatal: Persistent store URL is nil, cannot recover.");
        abort();
    }
}

- (void)configureMainContext {
    _mainContext = _persistentContainer.viewContext;
    _mainContext.automaticallyMergesChangesFromParent = YES;
    _mainContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
    _mainContext.undoManager = nil; // Disable undo manager for performance
}

#pragma mark - Context Management

- (NSManagedObjectContext *)newBackgroundContext {
    NSManagedObjectContext *backgroundContext = [_persistentContainer newBackgroundContext];
    backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
    backgroundContext.automaticallyMergesChangesFromParent = YES;
    backgroundContext.undoManager = nil;
    return backgroundContext;
}

#pragma mark - Save Operations

- (void)saveMainContext {
    NSManagedObjectContext *context = self.mainContext;
    if (!context) {
        NSLog(@"[CPCoreDataStack] saveMainContext: mainContext is nil.");
        return;
    }
    [context performBlock:^{
        [self saveContext:context];
    }];
}

- (void)saveContext:(NSManagedObjectContext *)context {
    if (!context) {
        NSLog(@"[CPCoreDataStack] saveContext: provided context is nil.");
        return;
    }

    if (!context.hasChanges) {
        return;
    }

    NSError *error = nil;
    BOOL success = [context save:&error];
    if (!success) {
        NSLog(@"[CPCoreDataStack] Failed to save context (%@): %@\nUserInfo: %@",
              context.concurrencyType == NSMainQueueConcurrencyType ? @"main" : @"background",
              error.localizedDescription,
              error.userInfo);
        // Log per-object validation errors if present
        NSArray *detailedErrors = error.userInfo[NSDetailedErrorsKey];
        if (detailedErrors.count > 0) {
            for (NSError *detailedError in detailedErrors) {
                NSLog(@"[CPCoreDataStack] Detailed error: %@", detailedError.localizedDescription);
            }
        }
    }
}

#pragma mark - Background Tasks

- (void)performBackgroundTask:(void (^)(NSManagedObjectContext *context))block {
    NSParameterAssert(block);
    NSManagedObjectContext *backgroundContext = [self newBackgroundContext];
    [backgroundContext performBlock:^{
        block(backgroundContext);
        [self saveContext:backgroundContext];
    }];
}

@end
