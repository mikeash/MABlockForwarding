
#import <objc/message.h>
#import "MABlockForwarding.h"

struct BlockDescriptor
{
    unsigned long reserved;
    unsigned long size;
    void *rest[1];
};

struct Block
{
    void *isa;
    int flags;
    int reserved;
    void *invoke;
    struct BlockDescriptor *descriptor;
};

enum {
    BLOCK_HAS_COPY_DISPOSE =  (1 << 25),
    BLOCK_HAS_CTOR =          (1 << 26), // helpers have C++ code
    BLOCK_IS_GLOBAL =         (1 << 28),
    BLOCK_HAS_STRET =         (1 << 29), // IFF BLOCK_HAS_SIGNATURE
    BLOCK_HAS_SIGNATURE =     (1 << 30), 
};

static void *BlockImpl(id block)
{
    return ((struct Block *)block)->invoke;
}

static const char *BlockSig(id blockObj)
{
    struct Block *block = (void *)blockObj;
    struct BlockDescriptor *descriptor = block->descriptor;
    
    assert(block->flags & BLOCK_HAS_SIGNATURE);
    
    int index = 0;
    if(block->flags & BLOCK_HAS_COPY_DISPOSE)
        index += 2;
    
    return descriptor->rest[index];
}

@interface NSInvocation (PrivateHack)
- (void)invokeUsingIMP: (IMP)imp;
@end

@interface MAFakeBlock : NSObject
{
    int _flags;
    int _reserved;
    IMP _invoke;
    struct BlockDescriptor *_descriptor;
    
    id _forwardingBlock;
    BlockInterposer _interposer;
}

- (id)initWithBlock: (id)block interposer: (BlockInterposer)interposer;

@end

@implementation MAFakeBlock

- (id)initWithBlock: (id)block interposer: (BlockInterposer)interposer
{
    if((self = [super init]))
    {
        _forwardingBlock = [block copy];
        _interposer = [interposer copy];
        
        // NB: The bottom 16 bits represent the block's retain count
        _flags = ((struct Block *) block)->flags & ~0xFFFF;
        
        _descriptor = malloc(sizeof(struct BlockDescriptor));
        _descriptor->size = class_getInstanceSize([self class]);
        
        int index = 0;
        if (_flags & BLOCK_HAS_COPY_DISPOSE)
            index += 2;
        
        _descriptor->rest[index] = (void *) BlockSig(block);
        
        if (_flags & BLOCK_HAS_STRET)
            _invoke = (IMP) _objc_msgForward_stret;
        else
            _invoke = _objc_msgForward;
    }
    return self;
}

- (void)dealloc
{
    [_forwardingBlock release];
    [_interposer release];
    free(_descriptor);
    
    [super dealloc];
}

- (NSMethodSignature *)methodSignatureForSelector: (SEL)sel
{
    const char *types = BlockSig(_forwardingBlock);
    NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes: types];
    while([sig numberOfArguments] < 2)
    {
        types = [[NSString stringWithFormat: @"%s%s", types, @encode(void *)] UTF8String];
        sig = [NSMethodSignature signatureWithObjCTypes: types];
    }
    return sig;
}

- (void)forwardInvocation: (NSInvocation *)inv
{
    [inv setTarget: _forwardingBlock];
    _interposer(inv, ^{
        [inv invokeUsingIMP: BlockImpl(_forwardingBlock)];
    });
}

- (id)copyWithZone: (NSZone *)zone
{
    return [self retain];
}

@end

id MAForwardingBlock(BlockInterposer interposer, id block)
{
    return [[[MAFakeBlock alloc] initWithBlock: block interposer: interposer] autorelease];
}

id MAMemoize(id block) {
    NSMutableDictionary *memory = [NSMutableDictionary dictionary];
    
    return MAForwardingBlock(^(NSInvocation *inv, void (^call)(void)) {
        NSMethodSignature *sig = [inv methodSignature];
        NSMutableArray *args = [NSMutableArray array];
        
        for(unsigned i = 1; i < [sig numberOfArguments]; i++)
        {
            id arg = nil;
            const char *type = [sig getArgumentTypeAtIndex: i];
            if(type[0] == @encode(id)[0])
            {
                [inv getArgument: &arg atIndex: i];
                if([arg conformsToProtocol: @protocol(NSCopying)])
                    arg = [[arg copy] autorelease];
            }
            else if(type[0] == @encode(char *)[0])
            {
                char *str;
                [inv getArgument: &str atIndex: i];
                arg = [NSData dataWithBytes: str length: strlen(str)];
            }
            else
            {
                NSUInteger size;
                NSGetSizeAndAlignment(type, &size, NULL);
                arg = [NSMutableData dataWithLength: size];
                [inv getArgument: [arg mutableBytes] atIndex: i];
            }
            
            if(!arg)
                arg = [NSNull null];
            
            [args addObject: arg];
        }
        
        const char *type = [sig methodReturnType];
        BOOL isObj = type[0] == @encode(id)[0];
        BOOL isCStr = type[0] == @encode(char *)[0];
        
        id result;
        @synchronized(memory)
        {
            result = [[[memory objectForKey: args] retain] autorelease];
        }
        
        if(!result)
        {
            call();
            if(isObj)
            {
                [inv getReturnValue: &result];
            }
            else if(isCStr)
            {
                char *str;
                [inv getReturnValue: &str];
                result = str ? [NSData dataWithBytes: str length: strlen(str) + 1] : NULL;
            }
            else
            {
                NSUInteger size;
                NSGetSizeAndAlignment(type, &size, NULL);
                result = [NSMutableData dataWithLength: size];
                [inv getReturnValue: [result mutableBytes]];
            }
            
            if(!result)
                result = [NSNull null];
            
            @synchronized(memory)
            {
                [memory setObject: result forKey: args];
            }
        }
        else
        {
            if(result == [NSNull null])
                result = nil;
            
            if(isObj)
            {
                [inv setReturnValue: &result];
            }
            else if(isCStr)
            {
                const char *str = [result bytes];
                [inv setReturnValue: &str];
            }
            else
            {
                [inv setReturnValue: [result mutableBytes]];
            }
        }
    }, block);
}
