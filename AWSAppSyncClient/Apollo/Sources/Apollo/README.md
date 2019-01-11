## AWSAppSync and Apollo

The AWSAppSync SDK is based off of the [Apollo project](https://github.com/apollographql/apollo-ios).

AWSAppSync forked 0.7.x of the Apollo code to make some changes we needed to support AppSync:

- Expose whether a result was served from service or cache. ([Code](https://github.com/awslabs/aws-mobile-appsync-sdk-ios/commit/bd5aebd97968ee135d4d77c490c399ec5c0a7d78#diff-fa9a094371bc4d792b5b0d8c25fc03e5R3)
- Trigger watches when writing to cache within a transaction (Part of AppSync v2.6.14) https://github.com/awslabs/aws-mobile-appsync-sdk-ios/commit/bd5aebd97968ee135d4d77c490c399ec5c0a7d78 
- Allow null result values to be propagated in selection sets as long as the underlying type is optional. This allows subscriptions to have a selection set that includes fields not delivered by the mutation, as in:
    ```graphql
    mutation {
      createPost(name: "Test", created: "2019-01-01T01:02:03Z", author: "The author") {
        name
      }
    }

    subscription {
      onCreatePost {
        name
        created
        author
      }
    }
    ```
- Added additional tests to cover cache policy behavior
- Enhanced the auto-generated "StarWarsAPI" to include an "optionalString" field, to ensure that null optional values are properly handled by cache policies


We've also ported the following features from later versions of the core Apollo repo:

- [`clearCache`](https://github.com/awslabs/aws-mobile-appsync-sdk-ios/pull/141/)
