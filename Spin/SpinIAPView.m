//
//  SpinIAPView.m
//  Spin
//
//  Copyright (c) 2013 Apportable. All rights reserved.
//

// For testing IAP

#import "SpinIAPView.h"

@interface SpinIAPView() {
    NSMutableArray *_buttons;
    NSMutableDictionary *_buttonToProduct;
    SKProductsRequest *_productsRequest;
    SKProductsResponse *_productsList;
}

@end

@implementation SpinIAPView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code
        [self initView];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super initWithCoder:decoder];
    if (self) {
        // Initialization code
        [self initView];
    }
    return self;
}


- (void)initView
{    
    _buttons = [NSMutableArray array];
    _buttonToProduct = [NSMutableDictionary dictionary];
    [self setBackgroundColor:[UIColor grayColor]];
    NSLog(@"-------------------------initWithView");
    
    [[SKPaymentQueue defaultQueue] addTransactionObserver:self];

    double delayInSeconds = 3.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [self requestProductData];
#ifdef APPORTABLE
        //on IABv3, restoring purchases is cheap. 
        //we should do this to find any consumable purchases that are consumable 
        //and consume them before the user buys again to prevent errors
        [self restorePurchases];
#endif
    });
}

- (void)requestProductData
{
    NSMutableSet *productIdentifiers = [NSMutableSet set];
    [productIdentifiers addObject:@"com.apportable.spin.nonconsumable1"];
    for (int i=1;i<=10;i++){
        [productIdentifiers addObject:[NSString stringWithFormat:@"com.apportable.spin.consumable%d",i]];
    }
    _productsRequest = [[SKProductsRequest alloc] initWithProductIdentifiers:productIdentifiers];
    [_productsRequest setDelegate:self];
    
    NSLog(@"Requesting IAP product data... %@", _productsRequest);
    [_productsRequest start];
}

- (void)purchaseItem:(UIButton *)sender
{
    SKProduct *product = _buttonToProduct[[NSValue valueWithNonretainedObject:sender]];
    NSLog(@"purchasing product %@", product);
    SKPayment *payment = [SKPayment paymentWithProduct:product];
    [[SKPaymentQueue defaultQueue] addPayment:payment];
}

-(void)restorePurchases
{
    NSLog(@"restoring purchases");
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}


#pragma mark -
#pragma mark SKProductsRequestDelegate methods

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response
{
    for (UIButton *button in _buttons){
        [button removeFromSuperview];
    }
    [_buttons removeAllObjects];
    [_buttonToProduct removeAllObjects];
    
    _productsList = response;
    
    NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
    [numberFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
    [numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
    
    NSArray *products = response.products;
    for (int i=0; i < [products count]; ++i) {
        SKProduct *product = [products objectAtIndex:i];
        if (product) {
            NSLog(@"Product id: %@" , product.productIdentifier);
            NSLog(@"Product title: %@" , product.localizedTitle);
            NSLog(@"Product description: %@" , product.localizedDescription);
            NSLog(@"Product price: %@" , product.price);
            NSLog(@"Product price locale: %@" , product.priceLocale);
            NSString *price;
#ifdef APPORTABLE
            price = [product performSelector:@selector(_priceString)];
#else
            [numberFormatter setLocale:product.priceLocale];
            price = [numberFormatter stringFromNumber:product.price];
#endif
            UIButton *button = [self addProductButtonWithName:product.productIdentifier price:price];
            [button setFrame:CGRectMake(10.0, 10.0 + (i*50.0), 300, 44)];
            [_buttons addObject:button];
            [_buttonToProduct setObject:product forKey:[NSValue valueWithNonretainedObject:button]];
        }
    }
    
    for (NSString *invalidProductId in response.invalidProductIdentifiers) {
        NSLog(@"INVALID PRODUCT ID: %@" , invalidProductId);
    }
}


-(UIButton *)addProductButtonWithName:(NSString *)product price:(NSString *)price {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    NSString *str = product;
    [button setTitle:str forState:UIControlStateNormal];
    [button setTitle:str forState:UIControlStateHighlighted];
    [button setTitle:str forState:UIControlStateSelected];
    [button setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
    [button setTitleColor:[UIColor greenColor] forState:UIControlStateHighlighted];
    [button setTitleColor:[UIColor greenColor] forState:UIControlStateSelected];
    [button setBackgroundColor:[UIColor redColor]];
    [self addSubview:button];
    [button addTarget:self action:@selector(purchaseItem:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

#pragma mark -
#pragma mark SKPaymentTransactionObserver methods

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions
{
    NSLog(@"----------------------------paymentQueue:updatedTransactions:");
    BOOL finish = YES;
    for (SKPaymentTransaction *txn in transactions) {
        switch (txn.transactionState) {
            case SKPaymentTransactionStatePurchasing:
                NSLog(@"SKPaymentTransactionStatePurchasing txn: %@", txn);
                break;
            case SKPaymentTransactionStatePurchased:
                NSLog(@"SKPaymentTransactionStatePurchased: %@", txn);
#ifdef APPORTABLE
                //in your app, you are going to have to know if the product is consumable or not.
                // in my test app, all consumable products have consumable in the product identifier
                if ([[[txn payment] productIdentifier] rangeOfString:@".consumable"].location != NSNotFound) {
                    NSLog(@"consuming product");
                    finish = [[SKPaymentQueue defaultQueue] consumePurchase:txn];
                    if (!finish){
                        NSLog(@"unable to consume product");
                    }
                }
#endif

                break;
            case SKPaymentTransactionStateFailed:
                NSLog(@"SKPaymentTransactionStateFailed: %@", txn);
                break;
            case SKPaymentTransactionStateRestored:
                NSLog(@"SKPaymentTransactionStateRestored: %@", txn);
                NSLog(@"Original transaction: %@", [txn originalTransaction]);
                NSLog(@"Original transaction payment: %@", [[txn originalTransaction] payment]);
#ifdef APPORTABLE
                //so deal with races, you should give credit here incase you haven't. it's up to you to give credit.
                //in your app, you are going to have to know if the product is consumable or not.
                //in my test app, all consumable products have consumable in the product identifier
                if ([[[txn payment] productIdentifier] rangeOfString:@".consumable"].location != NSNotFound) {
                    NSLog(@"consuming product");
                    finish = [[SKPaymentQueue defaultQueue] consumePurchase:txn];
                    if (!finish){
                        NSLog(@"unable to consume product");
                    }
                }
#endif

                break;
            default:
                NSLog(@"UNKNOWN SKPaymentTransactionState: %@", txn);
                break;
        }
        if (finish) {
            [[SKPaymentQueue defaultQueue] finishTransaction:txn];
        }
    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue removedTransactions:(NSArray *)transactions
{
    NSLog(@"----------------------------paymentQueue:removedTransactions:");
    for (SKPaymentTransaction *txn in transactions) {
        NSLog(@"removed transaction: %@", txn);
    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error
{
    NSLog(@"----------------------------paymentQueue:restoreCompletedTransactionsFailedWithError: %@", error);
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue
{
    NSLog(@"----------------------------paymentQueueRestoreCompletedTransactionsFinished:");
}

- (void)paymentQueue:(SKPaymentQueue *)queue updatedDownloads:(NSArray *)downloads
{
    NSLog(@"----------------------------paymentQueue:updatedDownloads:");
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect
{
    // Drawing code
}
*/

@end
