// The MIT License
//
// Copyright (c) 2013 Gwendal Roué
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import <objc/message.h>
#import <pthread.h>
#import "GRMustacheKeyAccess_private.h"
#import "JRSwizzle.h"


#if !defined(NS_BLOCK_ASSERTIONS)
// For testing purpose
BOOL GRMustacheKeyAccessDidCatchNSUndefinedKeyException;
#endif


// =============================================================================
#pragma mark - NSUndefinedKeyException prevention declarations

@interface NSObject(GRMustacheKeyAccessPreventionOfNSUndefinedKeyException)
- (id)GRMustacheKeyAccessValueForUndefinedKey_NSObject:(NSString *)key;
- (id)GRMustacheKeyAccessValueForUndefinedKey_NSManagedObject:(NSString *)key;
@end;


// =============================================================================
#pragma mark - GRMustacheKeyAccess

@implementation GRMustacheKeyAccess

+ (id)valueForMustacheKey:(NSString *)key inObject:(id)object
{
    if (object == nil) {
        return nil;
    }
    
    if (preventsNSUndefinedKeyException) {
        [GRMustacheKeyAccess startPreventingNSUndefinedKeyExceptionFromObject:object];
    }
    
    @try {
        // We don't want to use NSArray, NSSet and NSOrderedSet implementation
        // of valueForKey:, because they return another collection: see issue #21
        // and "anchored key should not extract properties inside an array" test
        // in src/tests/Public/v4.0/GRMustacheSuites/compound_keys.json
        if ([self objectIsFoundationCollectionWhoseImplementationOfValueForKeyReturnsAnotherCollection:object]) {
            static IMP NSObjectIMP;
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                NSObjectIMP = class_getMethodImplementation([NSObject class], @selector(valueForKey:));
            });
            return NSObjectIMP(object, @selector(valueForKey:), key);
        } else {
            return [object valueForKey:key];
        }
    }
    
    @catch (NSException *exception) {
        
        // Swallow NSUndefinedKeyException only
        
        if (![[exception name] isEqualToString:NSUndefinedKeyException]) {
            [exception raise];
        }
#if !defined(NS_BLOCK_ASSERTIONS)
        else {
            // For testing purpose
            GRMustacheKeyAccessDidCatchNSUndefinedKeyException = YES;
        }
#endif
    }
    
    @finally {
        if (preventsNSUndefinedKeyException) {
            [GRMustacheKeyAccess stopPreventingNSUndefinedKeyExceptionFromObject:object];
        }
    }
    
    return nil;
}

+ (BOOL)objectIsFoundationCollectionWhoseImplementationOfValueForKeyReturnsAnotherCollection:(id)object
{
    static CFMutableDictionaryRef cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    });
    
    Class klass = object_getClass(object);
    intptr_t result = (intptr_t)CFDictionaryGetValue(cache, klass);   // 0 = undefined, 1 = YES, 2 = NO
    if (!result) {
        Class NSOrderedSetClass = NSClassFromString(@"NSOrderedSet");
        result = ([klass isSubclassOfClass:[NSArray class]] ||
                  [klass isSubclassOfClass:[NSSet class]] ||
                  (NSOrderedSetClass && [klass isSubclassOfClass:NSOrderedSetClass])) ? 1 : 2;
        CFDictionarySetValue(cache, klass, (const void *)result);
    }
    return (result == 1);
}


// =============================================================================
#pragma mark - NSUndefinedKeyException prevention

static BOOL preventsNSUndefinedKeyException = NO;

#if TARGET_OS_IPHONE
// iOS never had support for Garbage Collector.
// Use fast pthread library.
static pthread_key_t GRPreventedObjectsStorageKey;
void freePreventedObjectsStorage(void *objects) {
    [(NSMutableSet *)objects release];
}
#define setupPreventedObjectsStorage() pthread_key_create(&GRPreventedObjectsStorageKey, freePreventedObjectsStorage)
#define getCurrentThreadPreventedObjects() (NSMutableSet *)pthread_getspecific(GRPreventedObjectsStorageKey)
#define setCurrentThreadPreventedObjects(objects) pthread_setspecific(GRPreventedObjectsStorageKey, objects)
#else
// OSX used to have support for Garbage Collector.
// Use slow NSThread library.
static NSString *GRPreventedObjectsStorageKey = @"GRPreventedObjectsStorageKey";
#define setupPreventedObjectsStorage()
#define getCurrentThreadPreventedObjects() (NSMutableSet *)[[[NSThread currentThread] threadDictionary] objectForKey:GRPreventedObjectsStorageKey]
#define setCurrentThreadPreventedObjects(objects) [[[NSThread currentThread] threadDictionary] setObject:objects forKey:GRPreventedObjectsStorageKey]
#endif

+ (void)preventNSUndefinedKeyExceptionAttack
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self setupNSUndefinedKeyExceptionPrevention];
    });
}

+ (void)setupNSUndefinedKeyExceptionPrevention
{
    preventsNSUndefinedKeyException = YES;
    
    // Swizzle [NSObject valueForUndefinedKey:]
    
    [NSObject jr_swizzleMethod:@selector(valueForUndefinedKey:)
                    withMethod:@selector(GRMustacheKeyAccessValueForUndefinedKey_NSObject:)
                         error:nil];
    
    
    // Swizzle [NSManagedObject valueForUndefinedKey:]
    
    Class NSManagedObjectClass = NSClassFromString(@"NSManagedObject");
    if (NSManagedObjectClass) {
        [NSManagedObjectClass jr_swizzleMethod:@selector(valueForUndefinedKey:)
                                    withMethod:@selector(GRMustacheKeyAccessValueForUndefinedKey_NSManagedObject:)
                                         error:nil];
    }
    
    setupPreventedObjectsStorage();
}

+ (void)startPreventingNSUndefinedKeyExceptionFromObject:(id)object
{
    NSMutableSet *objects = getCurrentThreadPreventedObjects();
    if (objects == NULL) {
        // objects will be released by the garbage collector, or by pthread
        // destructor function freePreventedObjectsStorage.
        //
        // Static analyzer can't see that, and emits a memory leak warning here.
        // This is a false positive: avoid the static analyzer examine this
        // portion of code.
#ifndef __clang_analyzer__
        objects = [[NSMutableSet alloc] init];
        setCurrentThreadPreventedObjects(objects);
#endif
    }
    
    [objects addObject:object];
}

+ (void)stopPreventingNSUndefinedKeyExceptionFromObject:(id)object
{
    [getCurrentThreadPreventedObjects() removeObject:object];
}

@end

@implementation NSObject(GRMustacheKeyAccessPreventionOfNSUndefinedKeyException)

// NSObject
- (id)GRMustacheKeyAccessValueForUndefinedKey_NSObject:(NSString *)key
{
    if ([getCurrentThreadPreventedObjects() containsObject:self]) {
        return nil;
    }
    return [self GRMustacheKeyAccessValueForUndefinedKey_NSObject:key];
}

// NSManagedObject
- (id)GRMustacheKeyAccessValueForUndefinedKey_NSManagedObject:(NSString *)key
{
    if ([getCurrentThreadPreventedObjects() containsObject:self]) {
        return nil;
    }
    return [self GRMustacheKeyAccessValueForUndefinedKey_NSManagedObject:key];
}

@end