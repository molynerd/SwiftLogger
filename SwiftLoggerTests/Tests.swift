//
//  SwiftLoggerTests.swift
//  SwiftLoggerTests
//
//  Created by Nicholas Molyneux on 9/14/16.
//  Copyright © 2016 Nicholas Molyneux. All rights reserved.
//

import XCTest
@testable import SwiftLogger

class SwiftLoggerTests: XCTestCase {
    var log = SwiftLogger()
    let logsToWrite = 1000
    var randomsUsed = [String]()
    
    override func setUp() {
        log.purgeLogs(nil)
        log.flushDelegate = nil
        log.tailDelegate = nil
        super.setUp()
    }
    
    override func tearDown() {
        log.purgeLogs(nil)
        log.flushDelegate = nil
        log.tailDelegate = nil
        super.tearDown()
    }
    
    //todo: concurrency test, make sure that i can't read/write at the same time
    
    /*
    *PERFORMANCE TESTS
    */
    func testWriteSingleLog_Small_Perf() {
        let r = self._rand()
        self.measure {
            self.log.info("performance run " + r)
        }
        self._validate(true)
    }

    func testWriteSingleLog_Small_ForceFlush_Perf() {
        let r = self._rand()
        self.measure {
            self.log.info("performance run" + r)
            self.log.shutdown()
        }
        self._validate(false)
    }
    
    func testWriteSingleLog_Large_Perf() {
        let r = self._rand()
        self.measure {
            //approx 5k of text
            self.log.info("Lorem ipsum dolor sit amet, consectetur adipiscing elit. In mattis lobortis eros, ut laoreet ligula convallis ut. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Phasellus ut porttitor metus, ut maximus nunc. Aliquam id ultrices ligula. Donec gravida, odio id consequat feugiat, lectus risus sollicitudin magna, sit amet tristique justo quam id arcu. Suspendisse turpis mi, hendrerit et ipsum eget, pretium volutpat urna. Duis varius diam sit amet lorem rutrum consequat. Fusce nec euismod lorem. Phasellus sit amet nisl odio. Maecenas viverra elit enim, nec mollis nisl auctor et. Etiam dignissim lacus sit amet libero vestibulum, at sodales est tristique. In aliquam vel neque vel aliquet. Phasellus vestibulum ipsum quis dui gravida, ac consequat ipsum porttitor. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Maecenas in massa sit amet lacus vulputate vehicula sed et diam. Morbi quis ligula bibendum risus aliquet porta. Morbi semper aliquam ante, mattis faucibus lorem ornare vitae. Suspendisse in pellentesque diam. Quisque viverra mi in orci molestie lacinia. Mauris ut nisl blandit, tincidunt tortor vel, pharetra nisi. Cras eu sem risus. Sed porttitor bibendum malesuada. Maecenas convallis dui sed massa lacinia, non lacinia arcu malesuada. Donec vel augue nec augue eleifend posuere eget sed mi. Maecenas et massa pellentesque, feugiat dui in, volutpat velit. Donec congue fermentum nisi a rutrum. Nulla aliquet, dui sit amet congue dapibus, quam odio sodales ante, in ultricies velit tortor sit amet odio. Cras sit amet tortor sem. Aenean congue orci sed nibh viverra rutrum. Nullam ac magna justo. Aliquam eget pretium dolor. Aenean posuere leo a leo consequat convallis. Nunc sollicitudin tortor vel quam finibus, vel maximus arcu dictum. Vivamus ultricies velit ornare neque facilisis, eget pellentesque nunc eleifend. Duis mattis commodo dolor, et scelerisque dolor tincidunt vitae. Nulla luctus odio id consequat congue. In vitae sagittis metus. Sed in lectus in nulla malesuada luctus id nec tortor. Sed bibendum metus varius, auctor lectus sit amet, viverra ex. Sed sit amet ultricies augue, non feugiat purus. Curabitur faucibus velit nec vehicula rutrum. Nullam efficitur dui nisi, sit amet bibendum nunc elementum vitae. Ut venenatis ornare mauris efficitur commodo. Aenean consequat at leo nec sagittis. Aliquam vel urna sagittis, fermentum est a, consectetur ipsum. Phasellus egestas urna bibendum, posuere ante a, tristique mi. Donec rutrum ultrices dui nec volutpat. Fusce lectus lorem, convallis ac semper eget, scelerisque a ipsum. Donec dictum purus tincidunt tellus auctor finibus. Donec erat sem, maximus sed velit id, viverra tempus dolor. Donec imperdiet urna tortor, nec lobortis libero vehicula pharetra. Suspendisse in dui elit. Nam quis sapien finibus, dignissim nulla eu, volutpat risus. Pellentesque ut libero orci. Quisque eget est ultricies, volutpat tortor quis, condimentum ligula. Etiam convallis metus mauris. Morbi efficitur mi sit amet ullamcorper eleifend. Duis tempor vestibulum orci et viverra. In sit amet tincidunt sapien. Duis quis diam lobortis, pulvinar erat in, mollis lectus. Vivamus libero tortor, efficitur a imperdiet nec, tincidunt nec arcu. Pellentesque elementum nisl sed massa sagittis, ac rhoncus ante tempus. Etiam consequat varius purus a porttitor. Vivamus dui arcu, elementum sit amet arcu posuere, aliquet tempus nisi. Fusce et gravida mi. Pellentesque habitant morbi tristique senectus et netus et malesuada fames ac turpis egestas. Cras pharetra mi libero, nec pellentesque nunc sagittis non. Quisque nisi metus, tempus at nunc eu, placerat posuere velit. Curabitur quis rutrum nibh, vel posuere enim. Fusce in sapien vitae lectus maximus finibus. Sed a velit porta, gravida felis ut, posuere augue. Vestibulum nulla ex, facilisis id leo vel, varius varius enim. Vivamus aliquet porta faucibus. Integer quis egestas ipsum, in rhoncus mauris. Ut pellentesque turpis ac posuere fermentum. Fusce augue leo, efficitur ac turpis tincidunt, molestie ornare nisl. Donec eu ipsum porta, aliquam ligula vel, placerat odio. Praesent turpis lorem, feugiat quis odio non, dictum commodo augue. Pellentesque dictum faucibus vulputate. Integer blandit lacus quis mi bibendum, quis porta orci aliquet. Proin convallis, massa vel pretium dictum, sem diam ornare sapien, ac consequat dolor justo ut diam. Maecenas ut hendrerit velit. Cras quis dolor et nunc tempus auctor. Aliquam egestas, leo id porttitor commodo, felis lectus cursus sapien, facilisis semper odio ipsum ut felis. Donec blandit aliquet convallis. Vestibulum magna dui, pretium a ultricies quis, viverra ut magna. Integer fringilla id erat vitae rhoncus. Quisque ex erat, vestibulum quis ornare eu, porta quis lorem. Donec convallis aliquet erat, vitae aliquet nunc malesuada nec. Sed ac viverra quam, gravida dapibus justo. Donec in sem ipsum. Fusce elementum neque libero, eu faucibus libero mollis sed. " + r)
        }
        self._validate(true)
    }
    
    func testWriteSingleLog_Large_ForceFlush_Perf() {
        let r = self._rand()
        self.measure {
            //approx 5k of text
            self.log.info("Lorem ipsum dolor sit amet, consectetur adipiscing elit. In mattis lobortis eros, ut laoreet ligula convallis ut. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Phasellus ut porttitor metus, ut maximus nunc. Aliquam id ultrices ligula. Donec gravida, odio id consequat feugiat, lectus risus sollicitudin magna, sit amet tristique justo quam id arcu. Suspendisse turpis mi, hendrerit et ipsum eget, pretium volutpat urna. Duis varius diam sit amet lorem rutrum consequat. Fusce nec euismod lorem. Phasellus sit amet nisl odio. Maecenas viverra elit enim, nec mollis nisl auctor et. Etiam dignissim lacus sit amet libero vestibulum, at sodales est tristique. In aliquam vel neque vel aliquet. Phasellus vestibulum ipsum quis dui gravida, ac consequat ipsum porttitor. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Maecenas in massa sit amet lacus vulputate vehicula sed et diam. Morbi quis ligula bibendum risus aliquet porta. Morbi semper aliquam ante, mattis faucibus lorem ornare vitae. Suspendisse in pellentesque diam. Quisque viverra mi in orci molestie lacinia. Mauris ut nisl blandit, tincidunt tortor vel, pharetra nisi. Cras eu sem risus. Sed porttitor bibendum malesuada. Maecenas convallis dui sed massa lacinia, non lacinia arcu malesuada. Donec vel augue nec augue eleifend posuere eget sed mi. Maecenas et massa pellentesque, feugiat dui in, volutpat velit. Donec congue fermentum nisi a rutrum. Nulla aliquet, dui sit amet congue dapibus, quam odio sodales ante, in ultricies velit tortor sit amet odio. Cras sit amet tortor sem. Aenean congue orci sed nibh viverra rutrum. Nullam ac magna justo. Aliquam eget pretium dolor. Aenean posuere leo a leo consequat convallis. Nunc sollicitudin tortor vel quam finibus, vel maximus arcu dictum. Vivamus ultricies velit ornare neque facilisis, eget pellentesque nunc eleifend. Duis mattis commodo dolor, et scelerisque dolor tincidunt vitae. Nulla luctus odio id consequat congue. In vitae sagittis metus. Sed in lectus in nulla malesuada luctus id nec tortor. Sed bibendum metus varius, auctor lectus sit amet, viverra ex. Sed sit amet ultricies augue, non feugiat purus. Curabitur faucibus velit nec vehicula rutrum. Nullam efficitur dui nisi, sit amet bibendum nunc elementum vitae. Ut venenatis ornare mauris efficitur commodo. Aenean consequat at leo nec sagittis. Aliquam vel urna sagittis, fermentum est a, consectetur ipsum. Phasellus egestas urna bibendum, posuere ante a, tristique mi. Donec rutrum ultrices dui nec volutpat. Fusce lectus lorem, convallis ac semper eget, scelerisque a ipsum. Donec dictum purus tincidunt tellus auctor finibus. Donec erat sem, maximus sed velit id, viverra tempus dolor. Donec imperdiet urna tortor, nec lobortis libero vehicula pharetra. Suspendisse in dui elit. Nam quis sapien finibus, dignissim nulla eu, volutpat risus. Pellentesque ut libero orci. Quisque eget est ultricies, volutpat tortor quis, condimentum ligula. Etiam convallis metus mauris. Morbi efficitur mi sit amet ullamcorper eleifend. Duis tempor vestibulum orci et viverra. In sit amet tincidunt sapien. Duis quis diam lobortis, pulvinar erat in, mollis lectus. Vivamus libero tortor, efficitur a imperdiet nec, tincidunt nec arcu. Pellentesque elementum nisl sed massa sagittis, ac rhoncus ante tempus. Etiam consequat varius purus a porttitor. Vivamus dui arcu, elementum sit amet arcu posuere, aliquet tempus nisi. Fusce et gravida mi. Pellentesque habitant morbi tristique senectus et netus et malesuada fames ac turpis egestas. Cras pharetra mi libero, nec pellentesque nunc sagittis non. Quisque nisi metus, tempus at nunc eu, placerat posuere velit. Curabitur quis rutrum nibh, vel posuere enim. Fusce in sapien vitae lectus maximus finibus. Sed a velit porta, gravida felis ut, posuere augue. Vestibulum nulla ex, facilisis id leo vel, varius varius enim. Vivamus aliquet porta faucibus. Integer quis egestas ipsum, in rhoncus mauris. Ut pellentesque turpis ac posuere fermentum. Fusce augue leo, efficitur ac turpis tincidunt, molestie ornare nisl. Donec eu ipsum porta, aliquam ligula vel, placerat odio. Praesent turpis lorem, feugiat quis odio non, dictum commodo augue. Pellentesque dictum faucibus vulputate. Integer blandit lacus quis mi bibendum, quis porta orci aliquet. Proin convallis, massa vel pretium dictum, sem diam ornare sapien, ac consequat dolor justo ut diam. Maecenas ut hendrerit velit. Cras quis dolor et nunc tempus auctor. Aliquam egestas, leo id porttitor commodo, felis lectus cursus sapien, facilisis semper odio ipsum ut felis. Donec blandit aliquet convallis. Vestibulum magna dui, pretium a ultricies quis, viverra ut magna. Integer fringilla id erat vitae rhoncus. Quisque ex erat, vestibulum quis ornare eu, porta quis lorem. Donec convallis aliquet erat, vitae aliquet nunc malesuada nec. Sed ac viverra quam, gravida dapibus justo. Donec in sem ipsum. Fusce elementum neque libero, eu faucibus libero mollis sed. " + r)
            self.log.shutdown()
        }
        self._validate(false)
    }
    
    /*
    *FUNCTIONALITY TESTS
    */
    
    /**Writes some simple logs, with single items*/
    func testWriteSingleLog() {
        for i in 0...self.logsToWrite {
            self.log.info("\(i) write this to the log: \(self._rand())")
        }
        self._validate(true)
    }
    
    func testWriteMultipleLog() {
        for i in 0...self.logsToWrite {
            self.log.info("\(i) write these to the log", self._rand(), self._rand())
        }
        self._validate(true)
    }
    
    /*
    *DELEGATE TESTS
    */
    func testTailDelegate() {
        let tailDelegate = TailDelegate()
        self.log.tailDelegate = tailDelegate
        self.log.info("write this to the log: " + self._rand())
        XCTAssertNotNil(tailDelegate.theMessage, "The delegate was not informed of the tail write")
        self._validate(true)
    }
    
    func testFlushDelegate() {
        let flushDelegate = FlushDelegate()
        self.log.flushDelegate = flushDelegate
        self.log.info("write this to the log: " + self._rand())
        self.log.shutdown()
        XCTAssertNotNil(flushDelegate.flushWasManual, "The delegate was not informed of the flush")
        XCTAssertTrue(flushDelegate.flushWasManual!, "The delegate was informed that flush was not manual, but it was called manually")
        self._validate(false)
    }
    
    func testComboDelegate() {
        let comboDelegate = ComboDelegate()
        self.log.tailDelegate = comboDelegate
        self.log.flushDelegate = comboDelegate
        self.log.info("write this to the log: " + self._rand())
        XCTAssertNotNil(comboDelegate.theMessage, "The delegate was not informed of the tail write")
        self.log.shutdown()
        XCTAssertNotNil(comboDelegate.flushWasManual, "The delegate was not informed of the flush")
        XCTAssertTrue(comboDelegate.flushWasManual!, "The delegate was informed that flush was not manual, but it was called manually")
        self._validate(false)
    }
    
    /*
    *UTILITIES
    */
    //delegates
    class TailDelegate: SwiftLoggerTailDelegate {
        var theMessage: String?
        func swiftLogger(didWriteLogToTail message: String) {
            self.theMessage = message
        }
    }
    class FlushDelegate: SwiftLoggerFlushDelegate {
        var flushWasManual: Bool?
        func swiftLogger(didFlushTailToDisk wasManual: Bool) {
            self.flushWasManual = wasManual
        }
    }
    class ComboDelegate: SwiftLoggerFlushDelegate, SwiftLoggerTailDelegate {
        var theMessage: String?
        func swiftLogger(didWriteLogToTail message: String) {
            self.theMessage = message
        }
        var flushWasManual: Bool?
        func swiftLogger(didFlushTailToDisk wasManual: Bool) {
            self.flushWasManual = wasManual
        }
    }
    
    //gets a random value, adds it to the randomsUsed and returns it
    fileprivate func _rand() -> String {
        let t = arc4random_uniform(100000)
        let r = String(t)
        self.randomsUsed.append(r)
        return r
    }
    
    //validates that the random value used during execution actually showed up in the logs
    fileprivate func _validate(_ withPreShutDown: Bool) {
        if withPreShutDown {
            self.log.shutdown()
        }
        //get the logs that were written
        var logs: [String:String]?
        do {
            logs = try log.getLogs()
        } catch SwiftLoggerGetLogsError.failedEnumeratingDirectory(let error) {
            XCTFail(String(describing: error))
        } catch SwiftLoggerGetLogsError.bug(let errorMessage) {
            XCTFail(errorMessage)
        } catch {
            XCTFail("unknown getlogs error")
        }
        
        //smash all the logs together
        //apparently these aren't in the correct for dictionaries, so we need to loop through the keys, sorted
        var allLog = ""
        for key in logs!.keys.sorted() {
            allLog += logs![key]!
            allLog += "\n"
        }
        
        //make sure the random numbers existed somewhere
        var randomsNotWritten = [String]()
        for str in self.randomsUsed {
            if !allLog.contains(str) {
                randomsNotWritten.append(str)
            }
        }
        
        //make sure that the logs were written in order
        var lastNumber = -1
        var split = allLog.components(separatedBy: "\n")
        for i in 0..<split.count {
            let current = split[i]
            guard let firstSpace = current.characters.index(of: " ") else {
                continue
            }
            let charsUntilFirstSpace = current.substring(to: firstSpace)
            //skip the first 2 chars, since it should be this >"
            let trimmed = charsUntilFirstSpace.substring(from: charsUntilFirstSpace.characters.index(charsUntilFirstSpace.startIndex, offsetBy: 2))
            guard let num = Int(trimmed) else {
                continue
            }
            XCTAssertEqual(lastNumber + 1, num, "logs written out of order: preceding \(lastNumber + 1), current \(num)")
            lastNumber += 1
        }
        
        XCTAssertEqual(randomsNotWritten.count, 0, "numbers not writtern: " + randomsNotWritten.joined(separator: ","))
    }
}
