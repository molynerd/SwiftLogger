# SwiftLogger
A simple logging library for Swift 3.0

## Need to Create Bug Reports?
The goal of this library is to make it real easy to log information inside your application and access it when needed. Simply create a global logging instance, log when needed, then send the logs to your server.

### Startup
##### Anywhere in the global scope, create a SwiftLogger instance.

`static let log = SwiftLogger()`

### Usage
##### Now that you have a logger instance, create some logs.
You can create simple string logs

`log.info("this is an info log")`

Or log multiple things at once

`log.fatal("something bad happened, here's some data", myDictionaryVariable)`

You can think of it as an extension of `debugPrint()`

##### Ready to read what's in there?
The simplest way is to grab all files, send them to your server and purge them. First call `shutdown()`, which simply tells the logger to make sure everything is ready to be read (the logger still works afterward). Then consume and purge the logs.
```
log.shutdown()
let logs = try? log.getLogs().values
//todo: send the log strings to your server
//purge the logs
log.purgeLogs()
```
Need more specifics? `getLogs()` returns the name of the file and the contents, so you can decide how to deal with each set.
```
log.shutdown()
if let dict = try? log.getLogs() {
    for pair in dict {
        //todo: do something with the contents
        //pair.value
        //purge the file
        log.purgeLogs([pair.key])
    }
}
```

### Options
- Control where logging files are saved
- Control the size of files
- Control the maximum amount of storage to use for logging files
- Control the output format for logging messages
- Hook into delegates to have greater visibility on the logging tail, and writing to disk operations
- Decide how important logging is (if something bad happens in the logger, do you want the application to crash, or continue without logging)

## Roadmap

This is by no means ready for any production scenario. I'm hoping to it have it ready to go by the end of October, with some testing in a large application. There's still a number of features I plan to add, and test cases to cover. In any case, it does work, so try it out!
