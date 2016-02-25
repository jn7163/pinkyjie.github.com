title: Angular里的E2E测试
categories:
  - 前端开发
tags:
  - AngularJS
  - 集成测试
  - protractor
  - PageObject
  - ComponentObject
  - promise
  - ES6
  - angular1-webpack-starter
date: 2016-02-21 22:39:13
---

上一篇聊完了[单元测试](/2016/02/20/separation-of-concerns-in-unit-test/)，这一篇来说说E2E测试。单元测试着眼的是“关注分离”，测的是一些函数单元是不是工作正常，而E2E则是集成测试，从最终用户的角度来进行端到端（End To End）的测试，测一些用户场景是不是正常。这篇文章就来探讨一下写E2E测试的最佳实践，本文使用protractor 2.x和jasmine 2.x，但一些思路和想法同样适用于别的框架。

<!--more-->

### 使用mock API和非真实后台

这一点其实存在很大争议，很多人觉得E2E测试作为集成测试就应该使用纯真实的server环境，所有后台API都应该实打实。我个人认为E2E测试是更偏向于开发者的测试而不是QA的测试，QA的测试当然要“真枪实弹”，但开发者使用mock API我觉得更加方便。我认为好处主要有以下几点：

* mock的API不仅可以用于测试，还可以加速开发。现在的Web开发早已趋向彻底的前后分离，后端只提供API，其他的都归前端。前端在开发阶段就需要根据前后端商量好的contract来mock API，使得在后端API未完工的情况下可以方便的进行前端的开发。所以mock一次，开发和测试阶段都能用，划算啊！
* 迅速解决“前后端撕逼”问题。众所周知，**所有的bug都是前端bug**，因为QA测的是你的前端页面啊，不管bug是什么引起的，肯定都是报给前端啊。所以，前端每天要做的一件重要的事就是迅速分辨哪些bug是由后端API引起的。使用mock API跑E2E测试，就是要保证在后端API正常返回的情况下前端逻辑能正常工作。这样一旦E2E测试跑过了，就可以迅速撇清关系：对不起，请把这个bug assign给后台修！
* 节约测试成本。使用mock API使得E2E测试可以跑在自己的开发server上，不仅可以减轻测试 server的压力，更是避免了真实测试环境的一些资源消耗。
* 跑起来速度快！没了真实环境的束缚，API想几秒返回就几秒返回，测试跑起来自然非常快了。

说完了好处，来说说问题。使用mock API带来的最大问题就是，你需要保证你mock的逻辑与后台的真实逻辑是相匹配的。比如说，后台有DB，你也要有一个类似数据库的地方存数据；后台可以根据不同的输入返回正确的值或错误代码，你的mock同样需要做到这一点。在谈具体的解决方案之前，让我们先从文件夹结构说起，下图是我在项目中常用的E2E文件夹结构：

{% img center-img  http://7jptbo.com1.z0.glb.clouddn.com/images/e2e-testing-in-angular-1.png 图1 %}

e2e文件夹下分了mocks和specs两个目录，specs不多说，重点看看mocks目录。

* index.js：这个文件是“带mock API的app”的入口，来看一个简单的例子：

``` javascript index.js
angular.module('appTest', [
    app.name,
    'ngMockE2E'
])
    .service(MockData.name, MockData)
    .config(appTestConfig)
    .run(userServiceMock)
    .run(phoneServiceMock);
```

其中定义了新的module，它依赖原始的app的module，并在其上定义一些新的配置和service。

* e2e.config.js：这是“带mock API的app”的配置，就是上面代码第6行的`appTestConfig`，一般我们可以用它定义API的请求延迟。由于使用了mock API，HTTP请求是可以立即返回的，为了让其更逼真，我们可以使用interceptor来监听所有`/api`开头的请求，让其过几秒再返回，以此来模拟真实的环境。

``` javascript e2e.config.js
appTestConfig.$inject = ['$httpProvider'];
function appTestConfig ($httpProvider) {
    $httpProvider.interceptors.push(apiDelayInterceptor);
    apiDelayInterceptor.$inject = ['$timeout', '$q'];
    function apiDelayInterceptor ($timeout, $q) {
        return {
            response (response) {
                // all API response will be delayed 1s to simulate real network
                const delay = 1000;
                if (response.config.url.match(/^api\//)) {
                    const d = $q.defer();
                    $timeout(() => {
                        d.resolve(response);
                    }, delay);
                    return d.promise;
                }
                return response;
            }
        };
    }
}
export default appTestConfig;
```

* e2e.data.js：这个文件定义了一个service（就是index里的`MockData`），它的作用就是我们前面提到的DB，它包含API要返回的各种数据。之所以将它定义为service，是利用service单例的特性，在E2E测试中，只要页面不刷新，前一个请求对数据的写操作就可以反映到后一个请求的读操作中，这样就跟真实环境的DB很类似了。
* e2e.phone.js/e2e.user.js：这两个文件分别对应原始app中定义的service，针对每个service都要有这么一个文件，这个文件的作用就是mock原始service里的各种API请求。来看一个登录API的例子：

``` javascript
userServiceMock.$inject = ['MockData', '$httpBackend'];
function userServiceMock (MockData, $httpBackend) {
    $httpBackend.whenPOST('api/user/login').respond(loginHandler);
    function loginHandler (method, url, data) {
        const req = JSON.parse(data);
        if (req.email === 'error@error.com') {
            return [200, {
                code: 1,
                message: 'LOGIN_WRONG_EMAIL_PASSWORD_PAIR',
                result: null
            }];
        } else if (req.email === 'lock@lock.com') {
            return [200, {
                code: 1,
                message: 'LOGIN_USER_IN_LOCK',
                result: null
            }];
        }
        MockData.loginStatus = true;
        return [200, {
            code: 0, message: null,
            result: {
                user: MockData.userInfo
            }
        }];
    }
}
export default userServiceMock;
```

可以看到，为了让其更逼真，我们可以根据请求发过来的不同数据来mock不同的响应，给出不同的错误代码，这样在E2E测试里我们就可以模拟更多的用户场景了。

### PageObject应该包含啥

PageObject是protractor官方推荐的[最佳实践](http://www.protractortest.org/#/page-objects#with-pageobjects)，它最大的好处就是将页面元素的选择器与测试本身隔离开，这样一旦页面结构发生变化，只需要更新PageObject即可，测试部分的代码不用变动。在[官方的例子](http://www.protractortest.org/#/page-objects#with-pageobjects)中，PageObject除了包含元素的定义以外，还包含一个`get()`函数来加载这个页面，包含两个其他函数来对元素进行输入和获取文字的操作。对于这个例子我持有保留意见，我的看法是好的PageObject应该包含以下这些东西：

* `load()`或`get()`函数，用来加载页面。
* 页面上所有测试需要用到的元素。
* 页面测试需要用到的数据，比如测试表单页面时需要填入的测试数据。
* 共享的测试用例，比如多个测试用例可能都需要用到公用的代码来assert特定的逻辑，那么这个公用逻辑可以作为函数提出来放入PageObject。
* 不要包含对元素的操作函数，像官方例子中的函数，只是简单的在元素上调用`.sendKey(xxx)`或`getText()`，我认为没必要将其封装成函数，直接写会更加直观，看测试代码的人也比较容易明白。
* 每个PageObject单独放一个文件，然后每个文件export这个class，这样一来，如果其他的PageObject依赖这个页面，可以方便的引入。

另外，ES6让继承写起来更方便了，我们完全可以打开脑洞，给所用的PageObject来一个基类：`BasePageObject`，来看一个例子（完整的实现可以看[这里](https://github.com/PinkyJie/angular1-webpack-starter/blob/master/source/test/e2e/helper.js)）：

``` javascript
class BasePageObject {
    constructor (url) {
        Object.assign(this, {url});

        this.ele = this._getAllElements();
        this.mainTitle = 'Aio Angular App';
    }

    load () {
        browser.get(`${browser.baseUrl}/${this.url}`);
    }

    getHeader () {...}
    getFooter () {...}
    getSidebar () {...}
    getBreadcrumb () {...}
    getModal () {...}

    // shared test case
    assertCorrectLayout (config) {...}
}
```

BasePageObject包含所有PageObject都会使用到的公用函数，它的构造函数接收一个url作用参数，这个url被`load()`函数使用来加载页面，它是子类继承后在子类构造函数中通过`super(xxx)`来传入的。另外它调用了一个`_getAllElements()`的函数获得所有元素的定义并将其挂在`this.ele`对象上方便使用，而这个`_getAllElements`也是要靠子类自己来实现的。除此之外，我们看到第13-17行定义了四个函数用来获取一些公共的布局组件，因为基本各个页面都包含这些组件，放在基类中子类就可以直接用了。最后基类还包含了公共的测试用例函数`assertCorrectLayout()`，它接受一个config。从函数名字就可以大致猜到它的作用：每个页面可能都要测试一些公共的布局，比如页面的URL、标题是不是正确啊，header和footer显示是否正常，sidebar和breadcrumb导航是不是能正常工作等等。这些测试每个页面都做，所以把它放在基类中，子类只需要传入一个配置对象即可。来看一个子类PageObject的例子：

``` javascript
import LoginPage from './login.page';
// phone page object
class PhonePage extends browser._BasePageObject {
    constructor () {
        super('phone');
    }

    _getAllElements () {
        const $page = $('.phone-main-view');
        return {
            addNewBtn: $page.$('.btn-add-new'),
        };
    }

    // overrite load function to support login
    load () {
        super.load();
        const loginPage = new LoginPage();
        browser._.expectUrlToMatch(loginPage.url);
        loginPage.loginWithCredential('f@f', 'f');
        browser._.expectUrlToMatch(this.url);
    }
}
```

可以看到，继承了父类后，子类的PageObject要做的就是：

* 子类构造函数中调用父类的构造函数并传入自己的URL。
* 实现`_getAllElements`函数，定义自己的页面元素。
* 根绝需要覆盖父类的`load()`函数。在这个例子中，假设phone页面需要登录后才能查看，那么直接访问`/phone`就会被重定向到login页面，那我们就需要依赖LoginPageObject的一些定义和函数，如这里的登录逻辑，成功登录后才能看到自己的页面。所以对于需要登录的页面，我们都要覆盖父类的load函数。

> load函数里调用了一些`browser._`上的函数，这是我们自己定义的helper函数，后面会讲到。

### PageObject里的元素该咋定义

看到这个标题有人会问：这算问题吗？那我换个方式问，挂在`this.ele`上的（也就是`_getAllElements()`函数返回的）应该是选择器本身`.xxx`还是element包装过的对象`$(.xxx)`呢？从使用者的角度讲，当然是包装过的对象了，因为方便直接调用上面的一些函数啊。但有些情况下，你还是需要选择器的，举个例子：一个表格里四行三列，行选择器是`.row`，列选择器分别是`.col1/.col2/.col3`等。测试里可能需要验证每一个格子里的文字，我们不可能把12个元素都写死放在ele变量上，如何更方便的解决这种需求呢？我的方案是这样的：

``` javascript
_getAllElements () {
    const $table = $('.table');
    return {
        row: {
            view: $page.$$('.row'),
            col1: '.col1',
            col2: '.col2',
            col3: '.col3'
        }
    };
}
```

可以看到，我们只返回一个`row`的元素，它是一个对象，里面的view属性返回包装过的多个元素（`$$`等价于`element.all`），其他属性则是它的子元素选择器。简单的说，存在多个实例的父元素（如表格的行）我们使用包装过的对象，对于每行的格子我们使用纯选择器。然后具体的测试中我们就可以这么写：

``` javascript
const rowList = page.ele.row;
expect(rowList.view.count()).toBe(4);
// first row
const first = rowList.view.get(0);
expect(first.$(rowList.col1).getText()).toBe(xxx);
```

遇到存在多个父元素，而每个父元素里又存在很多不同子元素的情况下，可以尝试使用这种方式来定义元素。定义的时候不显得重复，使用的时候也没有很麻烦。

### 使用ComponentObject

在[前面的文章](2016/01/31/component-based-development-with-angular-1x/)里我们讲过，在基于组件开发的实践中，页面其实是由各个组件搭成的。那么很自然的，PageObject也应该由ComponentObject来组成。同一个组件在不同的页面上重用时，组件内部的元素肯定都是一样的，一些逻辑也基本一致。所以ComponentObject里可以包含这个组件的所有元素以及一些公共的测试用例。考虑到Component在重用时，一般父级元素是不一样的，所以在ComponentObject的构造函数中可以传入一个parentElement的参数用来将组件内的选择器都限定在这个父选择器之内。来看一个例子：

``` javascript
// phone form component object
class PhoneFormComp {
    constructor (parentElement) {
        const $form = parentElement.$('.phone-form-view');
        this.ele = {
            saveBtn: $form.$('.btn-save'),
            cancelBtn: $form.$('.btn-cancel')
        };
    }

    assertFormFieldError (field, isError, message) {}
    assertPhoneDetail (phone) {}
    assertEditPhoneDetail (phone) {}
    assertEditingForm (phone, isNew) {}
}
export default PhoneFormComp;
```

可以看到在这个Form组件的定义中，组件内所有元素都是定义在传入的父元素的基础上的，这样即便一个页面内有多个同样的组件也不会重复，使用的时候只要传入不同的父级元素即可：

``` javascript
import PhoneFormComp from './phone-form.comp';

// phone add page object
class PhoneAddPage extends browser._BasePageObject {
    _getAllElements () {
        const $page = $('.phone-add-view');
        return {
            form: new PhoneFormComp($page)
        };
    }
}
```

### 善用helper函数和自定义matcher

在写E2E测试的时候，我们可能会用到很多工具函数，比如说操作一个select框啊，操作一个DatePicker啊等等，这些操作可能在多个测试用例里都会用到，那么我们可以直接定义一个`E2EHelper`的class用来存放这些helper函数。在protractor的配置文件中，我们在onPrepare里引入这个class，并将其定义在`browser._`上，因为browser是所有的spec里默认都可以访问到的，所以很多全局变量都可以考虑挂在它上面。这样在spec文件的测试里就可以方便的使用`browser._.xxx`来调用这些函数了。

除了helper函数，有的时候我们可能还需要一些自定义的Matcher来扩展jasmine中没有的功能，比如最常用的判断一个元素是否含有某个class样式，与其每次都在测试用例里手写`expect(ele.getAttribute('class')).toContain(xxx)`，不如直接扩展jasmine定义自己的Matcher，语义上更容易理解。Matcher的定义也非常的简单，下面就是一个例子：

``` javascript
const customMatchers = {
    toHaveClass: () => {
        return {
            compare: (actual, expected) => {
                return {
                    pass: actual.getAttribute('class').then((classes) => {
                        return classes.split(' ').indexOf(expected) !== -1;
                    })
                };
            }
        };
    }
};
```

有了这个定义以后，我们在测试中就可以直接写`expect(ele).toHaveClass(xxx)`了。网上还有很多成熟的库，包含很多常用的Matcher，感兴趣的可以索索“protractor custom matcher”。自定义的Matcher也需要在onPrepare中初始化，我们在里面定义一个beforeEach函数，把自定义的Matcher加入到jasmine中去。看下面的例子，onPrepare中包含helper函数，上一节提到的BasePageObject，以及自定义的Matcher。

``` javascript
onPrepare: () => {
    const helper = require('./source/test/e2e/helper');
    browser._BasePageObject = helper.BasePageObject;
    browser._ = new helper.E2EHelper();
    beforeEach(() => {
        // add custom matchers
        jasmine.addMatchers(helper.customMatchers);
    });
}
```

### protractor的大部分函数都返回promise

这一点可能平时没有注意，其实protractor官方的文档里专门有[讲这个](http://www.protractortest.org/#/control-flow)。也就是说，平时我们使用的`.getText()`，`.isDisplayed()`，`.getAttribute()`等等返回的都是promise，之所以我们可以直接那么用，是因为jasmine的`expect()`函数真正expect的是promise resolve后的值。相信平时使用这些函数的时候倒不会犯什么错，最容易犯错的是，定义一些自己的函数时，比如下面的代码

``` javascript
if (ele.isDisplayed()) {
    // do something
} else {
    // do others
}
```

代码的原意是如果元素显示的话，我们做一些事情，不显示的话我们做别的。但事实是这个if判断永远为true，因为里面是一个promise！所以正确的写法应该是：

``` javascript
ele.isDisplayed().then((val) => {
    if (val) {
        // do something
    } else {
        // do others
    }
})
```

要时刻记住protractor里绝大部分的函数返回的都是promise，如果我们自定义的逻辑用到这些函数，就应该以处理promise的方式来处理它们。

### 其它小tip

最后说一些让protractor更加好用的小tip。

#### 让测试report更好看

protractor默认的测试report就是在命令行里输出`...F..F..`，这么丑的report能忍吗？叔能忍婶不能忍啊！在karma中我们有reporter这个选项，让我们可以配置友好的测试输出，但protractor似乎没有这个配置啊。别急，其实早有人解决了这个难题，试试[jasmine-spec-reporter](https://www.npmjs.com/package/jasmine-spec-reporter)吧。你要做的很简单：

``` javascript
// 禁用默认的输出
jasmineNodeOpts: {
    print: () => {}
}
// 添加新的reporter
onPrepare: () => {
    const SpecReporter = require('jasmine-spec-reporter');
    jasmine.getEnv().addReporter(new SpecReporter({
        displayStacktrace: 'all',
        displayFailuresSummary: false
    }));
}
```

再跑一下测试看看，结果是不是好看多了？

{% img center-img  http://7jptbo.com1.z0.glb.clouddn.com/images/e2e-testing-in-angular-2.png 图2 %}

除了这两个选项外，它还支持很多有意思的配置，具体可以探索它的[文档](https://www.npmjs.com/package/jasmine-spec-reporter)。

#### 失败时自动截图

由于测试都是自动化的，一旦跑失败我们除了看log找原因以外，如果有截图就更好了。其实截图也属于reporter的一种，借助插件[protractor-jasmine2-screenshot-reporter](https://www.npmjs.com/package/protractor-jasmine2-screenshot-reporter)我们就可以实现在E2E测试失败的时候自动保存当前网页的截图到指定文件夹。它的配置也很简单，与上面的reporter类似，也是直接往onPrepare里面添加代码：

``` javascript
const HtmlScreenshotReporter = require('protractor-jasmine2-screenshot-reporter');
jasmine.getEnv().addReporter(new HtmlScreenshotReporter({
    dest: `${e2eBaseFolder}/screenshots`,
    filename: 'e2e-report.html',
    captureOnlyFailedSpecs: true,
    reportOnlyFailedSpecs: false,
    pathBuilder: (currentSpec) => {
        return currentSpec.description.replace(/[ :]/g, '-');
    }
}));
```

除了截图，它还支持输出HTML格式的report（第4行），利用pathBuilder函数我们还可以指定截图文件的名称，上例中我们直接将失败的spec的description作为文件名保存。

#### ES6的报错行号

protractor 2.x需要手动引入babel来支持使用ES6来书写spec文件，至于配置文件本身，只要你的node版本够高（4.x）或使用`--harmony`也是可以用ES6来写的。但如果你在protractor的配置文件一开头就引入babel`require('babel-core/register');`就会发现，一旦spec报错，log里给出的报错行号是不对的，在protractor的issues里有人给出了[解决方案](https://github.com/angular/protractor/issues/2049#issuecomment-146357769)，其实只要在onPrepare里再引入babel即可。
