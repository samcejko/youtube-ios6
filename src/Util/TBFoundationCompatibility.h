#import <Foundation/Foundation.h>

// These selectors are implemented by TBFoundationCompatibility.m on iOS 5.
// Redeclarations make the backported API visible to availability checking.
@interface NSArray (TBEarlierFoundation)
- (id)firstObject;
- (id)objectAtIndexedSubscript:(NSUInteger)index;
@end
@interface NSMutableArray (TBEarlierFoundation)
- (void)setObject:(id)object atIndexedSubscript:(NSUInteger)index;
@end
@interface NSDictionary (TBEarlierFoundation)
- (id)objectForKeyedSubscript:(id)key;
@end
@interface NSMutableDictionary (TBEarlierFoundation)
- (void)setObject:(id)object forKeyedSubscript:(id<NSCopying>)key;
@end
