#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// Install only missing entry points, before the collection-view constructor runs.
// Some iOS 5 Foundation releases lack the public subscript/firstObject selectors.
static void TBAddMissing(Class cls, SEL destination, SEL implementation)
{
    if (class_getInstanceMethod(cls, destination)) return;
    Method method = class_getInstanceMethod(cls, implementation);
    class_addMethod(cls, destination, method_getImplementation(method), method_getTypeEncoding(method));
}

@implementation NSArray (TBEarlierFoundation)
+ (void)load
{
    TBAddMissing(self, @selector(firstObject), @selector(tb_firstObject));
    TBAddMissing(self, @selector(objectAtIndexedSubscript:), @selector(objectAtIndex:));
}
- (id)tb_firstObject { return self.count ? [self objectAtIndex:0] : nil; }
@end

@implementation NSMutableArray (TBEarlierFoundation)
+ (void)load { TBAddMissing(self, @selector(setObject:atIndexedSubscript:), @selector(tb_setObject:atIndex:)); }
- (void)tb_setObject:(id)object atIndex:(NSUInteger)index
{
    if (index == self.count) [self addObject:object];
    else [self replaceObjectAtIndex:index withObject:object];
}
@end

@implementation NSDictionary (TBEarlierFoundation)
+ (void)load { TBAddMissing(self, @selector(objectForKeyedSubscript:), @selector(objectForKey:)); }
@end

@implementation NSMutableDictionary (TBEarlierFoundation)
+ (void)load { TBAddMissing(self, @selector(setObject:forKeyedSubscript:), @selector(tb_setObject:forKey:)); }
- (void)tb_setObject:(id)object forKey:(id<NSCopying>)key
{
    if (object) [self setObject:object forKey:key];
    else [self removeObjectForKey:key];
}
@end
