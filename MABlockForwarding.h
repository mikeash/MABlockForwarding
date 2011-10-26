
#import <Foundation/Foundation.h>


typedef void (^BlockInterposer)(NSInvocation *inv, void (^call)(void));

id MAForwardingBlock(BlockInterposer interposer, id block);

id MAMemoize(id block);
