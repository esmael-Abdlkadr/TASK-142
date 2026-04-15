#import "CPTestCoreDataStack.h"

@interface CPTestCoreDataStack ()
@property (nonatomic, readwrite, strong) NSPersistentContainer *persistentContainer;
@property (nonatomic, readwrite, strong) NSManagedObjectContext *mainContext;
@end

@implementation CPTestCoreDataStack

#pragma mark - Singleton

+ (instancetype)sharedStack {
    static CPTestCoreDataStack *_shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _shared = [[CPTestCoreDataStack alloc] init];
    });
    return _shared;
}

#pragma mark - Init

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupInMemoryStore];
    }
    return self;
}

- (void)setupInMemoryStore {
    // Load the model from the main app bundle
    NSBundle *appBundle = [NSBundle bundleWithIdentifier:@"com.chargeprocure.ChargeProcure"];
    if (!appBundle) {
        // Fallback: search all loaded bundles for the Model.momd
        for (NSBundle *bundle in [NSBundle allBundles]) {
            NSURL *modelURL = [bundle URLForResource:@"Model" withExtension:@"momd"];
            if (modelURL) {
                appBundle = bundle;
                break;
            }
        }
    }
    if (!appBundle) {
        appBundle = [NSBundle mainBundle];
    }

    NSURL *modelURL = [appBundle URLForResource:@"Model" withExtension:@"momd"];
    NSManagedObjectModel *mom = nil;
    if (modelURL) {
        mom = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    }
    if (!mom) {
        // Last-resort: merge all models from all bundles
        mom = [NSManagedObjectModel mergedModelFromBundles:[NSBundle allBundles]];
    }

    NSAssert(mom != nil, @"CPTestCoreDataStack: Could not load managed object model named 'Model'.");

    _persistentContainer = [[NSPersistentContainer alloc] initWithName:@"Model"
                                                   managedObjectModel:mom];

    // Configure an in-memory store
    NSPersistentStoreDescription *storeDesc = [[NSPersistentStoreDescription alloc] init];
    storeDesc.type = NSInMemoryStoreType;
    storeDesc.shouldAddStoreAsynchronously = NO;

    _persistentContainer.persistentStoreDescriptions = @[storeDesc];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSError *loadError = nil;
    [_persistentContainer loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *desc, NSError *error) {
        loadError = error;
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

    NSAssert(loadError == nil,
             @"CPTestCoreDataStack: Failed to load in-memory store: %@", loadError);

    _mainContext = _persistentContainer.viewContext;
    _mainContext.automaticallyMergesChangesFromParent = YES;
    _mainContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
    _mainContext.undoManager = nil;
}

#pragma mark - Background Context

- (NSManagedObjectContext *)newBackgroundContext {
    NSManagedObjectContext *ctx = [_persistentContainer newBackgroundContext];
    ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
    ctx.automaticallyMergesChangesFromParent = YES;
    ctx.undoManager = nil;
    return ctx;
}

#pragma mark - Reset

- (void)resetAll {
    // Delete all objects in every entity known to the model
    [_mainContext performBlockAndWait:^{
        NSArray<NSEntityDescription *> *entities = self->_persistentContainer.managedObjectModel.entities;
        for (NSEntityDescription *entity in entities) {
            // Skip abstract entities
            if (entity.abstract) continue;
            NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:entity.name];
            request.includesPropertyValues = NO;

            NSError *fetchError = nil;
            NSArray *objects = [self->_mainContext executeFetchRequest:request error:&fetchError];
            for (NSManagedObject *obj in objects) {
                [self->_mainContext deleteObject:obj];
            }
        }
        NSError *saveError = nil;
        [self->_mainContext save:&saveError];
        if (saveError) {
            NSLog(@"[CPTestCoreDataStack] resetAll save error: %@", saveError);
        }
    }];
}

@end
