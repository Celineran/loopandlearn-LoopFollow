//
//  NightScout.swift
//  LoopFollow
//
//  Created by Jon Fawcett on 6/16/20.
//  Copyright © 2020 Jon Fawcett. All rights reserved.
//

import Foundation
import UIKit
import CoreMedia


extension MainViewController {

    
    //NS Cage Struct
    struct cageData: Codable {
        var created_at: String
    }
    
    //NS Basal Profile Struct
    struct basalProfileStruct: Codable {
        var value: Double
        var time: String
        var timeAsSeconds: Double
    }
    
    //NS Basal Data  Struct
    struct basalGraphStruct: Codable {
        var basalRate: Double
        var date: TimeInterval
    }
    
    //NS Bolus Data  Struct
    struct bolusGraphStruct: Codable {
        var value: Double
        var date: TimeInterval
        var sgv: Int
    }
    
    //NS Bolus Data  Struct
    struct carbGraphStruct: Codable {
        var value: Double
        var date: TimeInterval
        var sgv: Int
        var absorptionTime: Int
    }
    
    func isStaleData() -> Bool {
        if bgData.count > 0 {
            let now = dateTimeUtils.getNowTimeIntervalUTC()
            let lastReadingTime = bgData.last!.date
            let secondsAgo = now - lastReadingTime
            if secondsAgo >= 20*60 {
                return true
            } else {
                return false
            }
        } else {
            return false
        }
    }
    
    
    // Dex Share Web Call
    func webLoadDexShare(onlyPullLastRecord: Bool = false) {
        // Dexcom Share only returns 24 hrs of data as of now
        // Requesting more just for consistency with NS
        let graphHours = 24 * UserDefaultsRepository.downloadDays.value
        var count = graphHours * 12
        if onlyPullLastRecord { count = 1 }
        dexShare?.fetchData(count) { (err, result) -> () in
            
            // TODO: add error checking
            if(err == nil) {
                let data = result!
                
                // If Dex data is old, load from NS instead
                let latestDate = data[0].date
                let now = dateTimeUtils.getNowTimeIntervalUTC()
                if (latestDate + 330) < now && UserDefaultsRepository.url.value != "" {
                    self.webLoadNSBGData(onlyPullLastRecord: onlyPullLastRecord)
                    print("dex didn't load, triggered NS attempt")
                    return
                }
                
                // Dexcom only returns 24 hrs of data. If we need more, call NS.
                if graphHours > 24 && !onlyPullLastRecord && UserDefaultsRepository.url.value != "" {
                    self.webLoadNSBGData(onlyPullLastRecord: onlyPullLastRecord, dexData: data)
                } else {
                    self.ProcessDexBGData(data: data, onlyPullLastRecord: onlyPullLastRecord, sourceName: "Dexcom")
                }
            } else {
                // If we get an error, immediately try to pull NS BG Data
                if UserDefaultsRepository.url.value != "" {
                    self.webLoadNSBGData(onlyPullLastRecord: onlyPullLastRecord)
                }
                
                if globalVariables.dexVerifiedAlert < dateTimeUtils.getNowTimeIntervalUTC() + 300 {
                    globalVariables.dexVerifiedAlert = dateTimeUtils.getNowTimeIntervalUTC()
                    DispatchQueue.main.async {
                        //self.sendNotification(title: "Dexcom Share Error", body: "Please double check user name and password, internet connection, and sharing status.")
                    }
                }
            }
        }
    }
    
    // NS BG Data Web call
    func webLoadNSBGData(onlyPullLastRecord: Bool = false, dexData: [ShareGlucoseData] = []) {
        writeDebugLog(value: "Download: BG")
        
        // This kicks it out in the instance where dexcom fails but they aren't using NS &&
        if UserDefaultsRepository.url.value == "" {
            self.startBGTimer(time: 10)
            return
        }

        let graphHours = 24 * UserDefaultsRepository.downloadDays.value
        // Set the count= in the url either to pull day(s) of data or only the last record
        var urlBGDataPath: String = UserDefaultsRepository.url.value + "/api/v1/entries/sgv.json?count="
        if !onlyPullLastRecord {
            let startTimeString = dateTimeUtils.nowMinusNHoursTimeInterval(N: graphHours)
            urlBGDataPath += "1440&find[dateString][$gte]=" + startTimeString
        } else {
            urlBGDataPath += "1"
        }

        // URL processor
        if token != "" {
            urlBGDataPath += "&token=" + token
        }

        guard let urlBGData = URL(string: urlBGDataPath) else {
            // if we have Dex data, use it
            if !dexData.isEmpty {
                self.ProcessDexBGData(data: dexData, onlyPullLastRecord: onlyPullLastRecord, sourceName: "Dexcom")
                return
            }
            
            if globalVariables.nsVerifiedAlert < dateTimeUtils.getNowTimeIntervalUTC() + 300 {
                globalVariables.nsVerifiedAlert = dateTimeUtils.getNowTimeIntervalUTC()
                //self.sendNotification(title: "Nightscout Error", body: "Please double check url, token, and internet connection. This may also indicate a temporary Nightscout issue")
            }
            DispatchQueue.main.async {
                if self.bgTimer.isValid {
                    self.bgTimer.invalidate()
                }
                self.startBGTimer(time: 10)
            }
            return
        }
        var request = URLRequest(url: urlBGData)
        request.cachePolicy = URLRequest.CachePolicy.reloadIgnoringLocalCacheData
        
        // Downloader
        let getBGTask = URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil else {
                if globalVariables.nsVerifiedAlert < dateTimeUtils.getNowTimeIntervalUTC() + 300 {
                    globalVariables.nsVerifiedAlert = dateTimeUtils.getNowTimeIntervalUTC()
                    //self.sendNotification(title: "Nightscout Error", body: "Please double check url, token, and internet connection. This may also indicate a temporary Nightscout issue")
                }
                DispatchQueue.main.async {
                    if self.bgTimer.isValid {
                        self.bgTimer.invalidate()
                    }
                    self.startBGTimer(time: 10)
                }
                // if we have Dex data, use it
                if !dexData.isEmpty {
                    self.ProcessDexBGData(data: dexData, onlyPullLastRecord: onlyPullLastRecord, sourceName: "Dexcom")
                }
                return
                
            }
            guard let data = data else {
                if globalVariables.nsVerifiedAlert < dateTimeUtils.getNowTimeIntervalUTC() + 300 {
                    globalVariables.nsVerifiedAlert = dateTimeUtils.getNowTimeIntervalUTC()
                    //self.sendNotification(title: "Nightscout Error", body: "Please double check url, token, and internet connection. This may also indicate a temporary Nightscout issue")
                }
                DispatchQueue.main.async {
                    if self.bgTimer.isValid {
                        self.bgTimer.invalidate()
                    }
                    self.startBGTimer(time: 10)
                }
                return
                
            }
            
            let decoder = JSONDecoder()
            let entriesResponse = try? decoder.decode([ShareGlucoseData].self, from: data)
            if var nsData = entriesResponse {
                DispatchQueue.main.async {
                    // transform NS data to look like Dex data
                    for i in 0..<nsData.count {
                        // convert the NS timestamp to seconds instead of milliseconds
                        nsData[i].date /= 1000
                        nsData[i].date.round(FloatingPointRoundingRule.toNearestOrEven)
                    }
                    
                    // merge NS and Dex data if needed; use recent Dex data and older NS data
                    var sourceName = "Nightscout"
                    if !dexData.isEmpty {
                        let oldestDexDate = dexData[dexData.count - 1].date
                        var itemsToRemove = 0
                        while itemsToRemove < nsData.count && nsData[itemsToRemove].date >= oldestDexDate {
                            itemsToRemove += 1
                        }
                        nsData.removeFirst(itemsToRemove)
                        nsData = dexData + nsData
                        sourceName = "Dexcom"
                    }
                    
                    // trigger the processor for the data after downloading.
                    self.ProcessDexBGData(data: nsData, onlyPullLastRecord: onlyPullLastRecord, sourceName: sourceName)
                    
                }
            } else {
                if globalVariables.nsVerifiedAlert < dateTimeUtils.getNowTimeIntervalUTC() + 300 {
                    globalVariables.nsVerifiedAlert = dateTimeUtils.getNowTimeIntervalUTC()
                    //self.sendNotification(title: "Nightscout Failure", body: "Please double check url, token, and internet connection. This may also indicate a temporary Nightscout issue")
                }
                DispatchQueue.main.async {
                    if self.bgTimer.isValid {
                        self.bgTimer.invalidate()
                    }
                    self.startBGTimer(time: 10)
                }
                return
                
            }
        }
        getBGTask.resume()
    }
    
    // Dexcom BG Data Response processor
    func ProcessDexBGData(data: [ShareGlucoseData], onlyPullLastRecord: Bool, sourceName: String){
        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Process: BG") }
        
        let graphHours = 24 * UserDefaultsRepository.downloadDays.value
        
        let pullDate = data[data.count - 1].date
        let latestDate = data[0].date
        let now = dateTimeUtils.getNowTimeIntervalUTC()
        
        // Start the BG timer based on the reading
        let secondsAgo = now - latestDate
        
        DispatchQueue.main.async {
            // if reading is overdue over: 20:00, re-attempt every 5 minutes
            if secondsAgo >= (20 * 60) {
                self.startBGTimer(time: (5 * 60))
                print("##### started 5 minute bg timer")
                
            // if the reading is overdue: 10:00-19:59, re-attempt every minute
            } else if secondsAgo >= (10 * 60) {
                self.startBGTimer(time: 60)
                print("##### started 1 minute bg timer")
                
            // if the reading is overdue: 7:00-9:59, re-attempt every 30 seconds
            } else if secondsAgo >= (7 * 60) {
                self.startBGTimer(time: 30)
                print("##### started 30 second bg timer")
                
            // if the reading is overdue: 5:00-6:59 re-attempt every 10 seconds
            } else if secondsAgo >= (5 * 60) {
                self.startBGTimer(time: 10)
                print("##### started 10 second bg timer")
            
            // We have a current reading. Set timer to 5:10 from last reading
            } else {
                self.startBGTimer(time: 300 - secondsAgo + Double(UserDefaultsRepository.bgUpdateDelay.value))
                let timerVal = 310 - secondsAgo
                print("##### started 5:10 bg timer: \(timerVal)")
            }
        }
        
        // If we already have data, we're going to pop it to the end and remove the first. If we have old or no data, we'll destroy the whole array and start over. This is simpler than determining how far back we need to get new data from in case Dex back-filled readings
        if !onlyPullLastRecord {
            bgData.removeAll()
        } else if bgData[bgData.count - 1].date != pullDate {
            bgData.removeFirst()
            
        } else {
            if data.count > 0 {
                self.updateBadge(val: data[data.count - 1].sgv)
                if UserDefaultsRepository.speakBG.value {
                    speakBG(sgv: data[data.count - 1].sgv)
                }
            }
            return
        }
        
        // loop through the data so we can reverse the order to oldest first for the graph
        for i in 0..<data.count{
            let dateString = data[data.count - 1 - i].date
            if dateString >= dateTimeUtils.getTimeIntervalNHoursAgo(N: graphHours) {
                let reading = ShareGlucoseData(sgv: data[data.count - 1 - i].sgv, date: dateString, direction: data[data.count - 1 - i].direction)
                bgData.append(reading)
            }
            
        }

        viewUpdateNSBG(sourceName: sourceName)
    }
    
    // NS BG Data Front end updater
    func viewUpdateNSBG (sourceName: String) {
        DispatchQueue.main.async {
            if UserDefaultsRepository.debugLog.value {
                self.writeDebugLog(value: "Display: BG")
                self.writeDebugLog(value: "Num BG: " + self.bgData.count.description)
            }
            let entries = self.bgData
            if entries.count < 1 { return }
            
            self.updateBGGraph()
            self.updateStats()
            
            let latestEntryi = entries.count - 1
            let latestBG = entries[latestEntryi].sgv
            let priorBG = entries[latestEntryi - 1].sgv
            let deltaBG = latestBG - priorBG as Int
            
            self.serverText.text = sourceName
        
            var snoozerBG = ""
            var snoozerDirection = ""
            var snoozerDelta = ""
            
            self.BGText.text = bgUnits.toDisplayUnits(String(latestBG))
            snoozerBG = bgUnits.toDisplayUnits(String(latestBG))
            self.setBGTextColor()
            
            if let directionBG = entries[latestEntryi].direction {
                self.DirectionText.text = self.bgDirectionGraphic(directionBG)
                snoozerDirection = self.bgDirectionGraphic(directionBG)
                self.latestDirectionString = self.bgDirectionGraphic(directionBG)
            } else {
                self.DirectionText.text = ""
                snoozerDirection = ""
                self.latestDirectionString = ""
            }
            
            if deltaBG < 0 {
                self.DeltaText.text = bgUnits.toDisplayUnits(String(deltaBG))
                snoozerDelta = bgUnits.toDisplayUnits(String(deltaBG))
                self.latestDeltaString = String(deltaBG)
            } else {
                self.DeltaText.text = "+" + bgUnits.toDisplayUnits(String(deltaBG))
                snoozerDelta = "+" + bgUnits.toDisplayUnits(String(deltaBG))
                self.latestDeltaString = "+" + String(deltaBG)
            }
            self.updateBadge(val: latestBG)
            
            // Snoozer Display
            guard let snoozer = self.tabBarController!.viewControllers?[2] as? SnoozeViewController else { return }
            snoozer.BGLabel.text = snoozerBG
            snoozer.DirectionLabel.text = snoozerDirection
            snoozer.DeltaLabel.text = snoozerDelta
        }
    }
    
    // NS Device Status Web Call
    func webLoadNSDeviceStatus() {
        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Download: device status") }
        let urlUser = UserDefaultsRepository.url.value

        // NS Api is not working to find by greater than date
        var urlStringDeviceStatus = urlUser + "/api/v1/devicestatus.json?count=1"
        if token != "" {
            urlStringDeviceStatus += "&token=" + token
        }
        let escapedAddress = urlStringDeviceStatus.addingPercentEncoding(withAllowedCharacters:NSCharacterSet.urlQueryAllowed)
        guard let urlDeviceStatus = URL(string: escapedAddress!) else {
            if globalVariables.nsVerifiedAlert < dateTimeUtils.getNowTimeIntervalUTC() + 300 {
                globalVariables.nsVerifiedAlert = dateTimeUtils.getNowTimeIntervalUTC()
                //self.sendNotification(title: "Nightscout Failure", body: "Please double check url, token, and internet connection. This may also indicate a temporary Nightscout issue")
            }
            DispatchQueue.main.async {
                if self.deviceStatusTimer.isValid {
                    self.deviceStatusTimer.invalidate()
                }
                self.startDeviceStatusTimer(time: 10)
            }
            
            return
        }
        
        
        var requestDeviceStatus = URLRequest(url: urlDeviceStatus)
        requestDeviceStatus.cachePolicy = URLRequest.CachePolicy.reloadIgnoringLocalCacheData

        let deviceStatusTask = URLSession.shared.dataTask(with: requestDeviceStatus) { data, response, error in
            
            guard error == nil else {
                if globalVariables.nsVerifiedAlert < dateTimeUtils.getNowTimeIntervalUTC() + 300 {
                    globalVariables.nsVerifiedAlert = dateTimeUtils.getNowTimeIntervalUTC()
                    //self.sendNotification(title: "Nightscout Error", body: "Please double check url, token, and internet connection. This may also indicate a temporary Nightscout issue")
                }
                DispatchQueue.main.async {
                    if self.deviceStatusTimer.isValid {
                        self.deviceStatusTimer.invalidate()
                    }
                    self.startDeviceStatusTimer(time: 10)
                }
                return
            }
            
            guard let data = data else {
                if globalVariables.nsVerifiedAlert < dateTimeUtils.getNowTimeIntervalUTC() + 300 {
                    globalVariables.nsVerifiedAlert = dateTimeUtils.getNowTimeIntervalUTC()
                    //self.sendNotification(title: "Nightscout Error", body: "Please double check url, token, and internet connection. This may also indicate a temporary Nightscout issue")
                }
                DispatchQueue.main.async {
                    if self.deviceStatusTimer.isValid {
                        self.deviceStatusTimer.invalidate()
                    }
                    self.startDeviceStatusTimer(time: 10)
                }
                return
            }
            
            
            let json = try? (JSONSerialization.jsonObject(with: data) as? [[String:AnyObject]])
            if let json = json {
                DispatchQueue.main.async {
                    self.updateDeviceStatusDisplay(jsonDeviceStatus: json)
                }
            } else {
                if globalVariables.nsVerifiedAlert < dateTimeUtils.getNowTimeIntervalUTC() + 300 {
                    globalVariables.nsVerifiedAlert = dateTimeUtils.getNowTimeIntervalUTC()
                    //self.sendNotification(title: "Nightscout Error", body: "Please double check url, token, and internet connection. This may also indicate a temporary Nightscout issue")
                }
                DispatchQueue.main.async {
                    if self.deviceStatusTimer.isValid {
                        self.deviceStatusTimer.invalidate()
                    }
                    self.startDeviceStatusTimer(time: 10)
                }
                return
            }
        }
        deviceStatusTask.resume()
    }
    
    // NS Device Status Response Processor
    func predictionData(_ predictions: [Double], _ loopTimestamp: TimeInterval) {
        PredictionLabel.text = bgUnits.toDisplayUnits(String(Int(predictions.last!)))
        if UserDefaultsRepository.downloadPrediction.value && latestLoopTime < loopTimestamp {
            predictionData.removeAll()
            var predictionTime = loopTimestamp
            let toLoad = min(Int(UserDefaultsRepository.predictionToLoad.value * 12), predictions.count)
            for prediction in predictions[...toLoad] {
                predictionData.append(ShareGlucoseData(sgv: Int(round(prediction)), date: predictionTime, direction: "flat"))
                predictionTime += 300
            }

            let predMin = predictions.min()
            let predMax = predictions.max()
            tableData[9].value = bgUnits.toDisplayUnits(String(predMin!)) + "/" + bgUnits.toDisplayUnits(String(predMax!))
            
            updatePredictionGraph()
        }
    }
    
    func updateLoopData(_ deviceStatus: [String : AnyObject]) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate,
                                   .withTime,
                                   .withDashSeparatorInDate,
                                   .withColonSeparatorInTime]

        guard let loopRecord = deviceStatus["loop"] as! [String : AnyObject]? else { return }
        guard let loopTimestamp = formatter.date(from: (loopRecord["timestamp"] as! String))?.timeIntervalSince1970 else { return }

        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "lastLoopTime: " + String(loopTimestamp)) }

        UserDefaultsRepository.alertLastLoopTime.value = loopTimestamp
        if let failureReason = loopRecord["failureReason"] as! String? {
            latestLoopStatusString = "X"
            LoopStatusLabel.text = latestLoopStatusString
            if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Loop Failure: " + failureReason) }
            return
        }

        var wasEnacted = false
        if loopRecord["enacted"] is [String:AnyObject] {
            if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Loop: Was Enacted") }
            wasEnacted = true
        }

        if let iobdata = loopRecord["iob"] as? [String:AnyObject] {
            latestIOB = String(format:"%.2f U", (iobdata["iob"] as! Double))
            tableData[0].value = latestIOB
        }
        if let cobdata = loopRecord["cob"] as? [String:AnyObject] {
            latestCOB = String(format:"%.0f g", cobdata["cob"] as! Double)
            tableData[1].value = latestCOB
        }
        if let predictdata = loopRecord["predicted"] as? [String:AnyObject] {
            let prediction = predictdata["values"] as! [Double]
            predictionData(prediction, loopTimestamp)
        }
        if let recBolus = loopRecord["recommendedBolus"] as? Double {
            tableData[8].value = String(format:"%.2f U", recBolus)
        }
        if let loopStatus = loopRecord["recommendedTempBasal"] as? [String:AnyObject] {
            if let tempBasalTime = formatter.date(from: (loopStatus["timestamp"] as! String))?.timeIntervalSince1970 {
                var lastBGTime = loopTimestamp
                if bgData.count > 0 {
                    lastBGTime = bgData[bgData.count - 1].date
                }
                if UserDefaultsRepository.debugLog.value {
                    self.writeDebugLog(value: "tempBasalTime: " + String(tempBasalTime))
                    self.writeDebugLog(value: "lastBGTime: " + String(lastBGTime))
                    self.writeDebugLog(value: "wasEnacted: " + String(wasEnacted))
                }
                if tempBasalTime > lastBGTime && !wasEnacted {
                    latestLoopStatusString = "⏀"
                    LoopStatusLabel.text = latestLoopStatusString
                    if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Open Loop: recommended temp. temp time > bg time, was not enacted") }
                } else {
                    latestLoopStatusString = "↻"
                    LoopStatusLabel.text = latestLoopStatusString
                    if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Looping: recommended temp, but temp time is < bg time and/or was enacted") }
                }
            }
        } else {
            latestLoopStatusString = "↻"
            LoopStatusLabel.text = latestLoopStatusString
            if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Looping: no recommended temp") }
        }
        if ((TimeInterval(Date().timeIntervalSince1970) - loopTimestamp) / 60) > 15 {
            latestLoopStatusString = "⚠"
            LoopStatusLabel.text = latestLoopStatusString
        }
        latestLoopTime = loopTimestamp
    }
    
    func updateDeviceStatusDisplay(jsonDeviceStatus: [[String:AnyObject]]) {
        self.clearLastInfoData(index: 0)
        self.clearLastInfoData(index: 1)
        self.clearLastInfoData(index: 8)

        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Process: device status") }
        if jsonDeviceStatus.count == 0 {
            return
        }
        
        //Process the current data first
        guard let lastDeviceStatus = jsonDeviceStatus[0] as [String : AnyObject]? else {
            return
        }
        
        if let lastPumpRecord = lastDeviceStatus["pump"] as! [String : AnyObject]? {
            if lastPumpRecord["clock"] != nil {
                if let reservoirData = lastPumpRecord["reservoir"] as? Double {
                    latestPumpVolume = reservoirData
                    tableData[5].value = String(format:"%.0f U", reservoirData)
                } else {
                    latestPumpVolume = 50.0
                    tableData[5].value = "50+ U"
                }
            }
        } else {
            tableData[5].value = ""
        }

        if let uploader = lastDeviceStatus["uploader"] as? [String:AnyObject] {
            let upbat = uploader["battery"] as! Double
            tableData[4].value = String(format:"%.0f %%", upbat)
        } else {
            tableData[4].value = ""
        }

        updateLoopData(lastDeviceStatus)
        
        var oText = ""
        currentOverride = 1.0
        if let lastOverride = lastDeviceStatus["override"] as! [String : AnyObject]? {
            if lastOverride["active"] as! Bool {
                let lastCorrection  = lastOverride["currentCorrectionRange"] as! [String: AnyObject]
                if let multiplier = lastOverride["multiplier"] as? Double {
                    currentOverride = multiplier
                    oText += String(format: "%.0f %%", (multiplier * 100))
                } else {
                    oText += "100 %"
                }
                oText += " ("
                let minValue = lastCorrection["minValue"] as! Double
                let maxValue = lastCorrection["maxValue"] as! Double
                oText += bgUnits.toDisplayUnits(String(minValue)) + "-" + bgUnits.toDisplayUnits(String(maxValue)) + ")"
                
            }
        }
        tableData[3].value =  oText

        infoTable.reloadData()
        
        // Start the timer based on the timestamp
        let now = dateTimeUtils.getNowTimeIntervalUTC()
        let secondsAgo = now - latestLoopTime
        
        DispatchQueue.main.async {
            // if Loop is overdue over: 20:00, re-attempt every 5 minutes
            if secondsAgo >= (20 * 60) {
                self.startDeviceStatusTimer(time: (5 * 60))
                print("started 5 minute device status timer")
                
                // if the Loop is overdue: 10:00-19:59, re-attempt every minute
            } else if secondsAgo >= (10 * 60) {
                self.startDeviceStatusTimer(time: 60)
                print("started 1 minute device status timer")
                
                // if the Loop is overdue: 7:00-9:59, re-attempt every 30 seconds
            } else if secondsAgo >= (7 * 60) {
                self.startDeviceStatusTimer(time: 30)
                print("started 30 second device status timer")
                
                // if the Loop is overdue: 5:00-6:59 re-attempt every 10 seconds
            } else if secondsAgo >= (5 * 60) {
                self.startDeviceStatusTimer(time: 10)
                print("started 10 second device status timer")
                
                // We have a current Loop. Set timer to 5:10 from last reading
            } else {
                self.startDeviceStatusTimer(time: 310 - secondsAgo)
                let timerVal = 310 - secondsAgo
                print("started 5:10 device status timer: \(timerVal)")
            }
        }
    }
    
    // NS Cage Web Call
    func webLoadNSCage() {
        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Download: CAGE") }
        let urlUser = UserDefaultsRepository.url.value
        var urlString = urlUser + "/api/v1/treatments.json?find[eventType]=Site%20Change&count=1"
        if token != "" {
            urlString += "&token=" + token
        }
        
        guard let urlData = URL(string: urlString) else {
            return
        }
        var request = URLRequest(url: urlData)
        request.cachePolicy = URLRequest.CachePolicy.reloadIgnoringLocalCacheData
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil else {
                return
            }
            guard let data = data else {
                return
            }
            
            let decoder = JSONDecoder()
            let entriesResponse = try? decoder.decode([cageData].self, from: data)
            if let entriesResponse = entriesResponse {
                DispatchQueue.main.async {
                    self.updateCage(data: entriesResponse)
                }
            } else {
                return
            }
        }
        task.resume()
    }
    
    // NS Cage Response Processor
    func updateCage(data: [cageData]) {
        self.clearLastInfoData(index: 7)
        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Process: CAGE") }
        if data.count == 0 {
            return
        }
        
        let lastCageString = data[0].created_at
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate,
                                   .withTime,
                                   .withDashSeparatorInDate,
                                   .withColonSeparatorInTime]
        UserDefaultsRepository.alertCageInsertTime.value = formatter.date(from: (lastCageString))!.timeIntervalSince1970
        if let cageTime = formatter.date(from: (lastCageString))?.timeIntervalSince1970 {
            let now = dateTimeUtils.getNowTimeIntervalUTC()
            let secondsAgo = now - cageTime
            
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .positional // Use the appropriate positioning for the current locale
            formatter.allowedUnits = [ .day, .hour ] // Units to display in the formatted string
            formatter.zeroFormattingBehavior = [ .pad ] // Pad with zeroes where appropriate for the locale
            
            let formattedDuration = formatter.string(from: secondsAgo)
            tableData[7].value = formattedDuration ?? ""
        }
        infoTable.reloadData()
    }
    
    // NS Sage Web Call
    func webLoadNSSage() {
        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Download: SAGE") }
        
        let lastDateString = dateTimeUtils.nowMinus10DaysTimeInterval()
        let urlUser = UserDefaultsRepository.url.value
        var urlString = urlUser + "/api/v1/treatments.json?find[eventType]=Sensor%20Start&find[created_at][$gte]=" + lastDateString + "&count=1"
        if token != "" {
            urlString += "&token=" + token
        }
        
        guard let urlData = URL(string: urlString) else {
            return
        }
        var request = URLRequest(url: urlData)
        request.cachePolicy = URLRequest.CachePolicy.reloadIgnoringLocalCacheData
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil else {
                return
            }
            guard let data = data else {
                return
            }
            
            let decoder = JSONDecoder()
            let entriesResponse = try? decoder.decode([cageData].self, from: data)
            if let entriesResponse = entriesResponse {
                DispatchQueue.main.async {
                    self.updateSage(data: entriesResponse)
                }
            } else {
                return
            }
        }
        task.resume()
    }
    
    // NS Sage Response Processor
    func updateSage(data: [cageData]) {
        self.clearLastInfoData(index: 6)
        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Process/Display: SAGE") }
        if data.count == 0 {
            return
        }
        
        let lastSageString = data[0].created_at
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate,
                                   .withTime,
                                   .withDashSeparatorInDate,
                                   .withColonSeparatorInTime]
        UserDefaultsRepository.alertSageInsertTime.value = formatter.date(from: lastSageString)!.timeIntervalSince1970

        if UserDefaultsRepository.alertAutoSnoozeCGMStart.value && (dateTimeUtils.getNowTimeIntervalUTC() - UserDefaultsRepository.alertSageInsertTime.value < 7200){
            let snoozeTime = Date(timeIntervalSince1970: UserDefaultsRepository.alertSageInsertTime.value + 7200)
            UserDefaultsRepository.alertSnoozeAllTime.value = snoozeTime
            UserDefaultsRepository.alertSnoozeAllIsSnoozed.value = true
            guard let alarms = self.tabBarController!.viewControllers?[1] as? AlarmViewController else { return }
            alarms.reloadIsSnoozed(key: "alertSnoozeAllIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertSnoozeAllTime", setNil: false, value: snoozeTime)
        }
        
        if let sageTime = formatter.date(from: lastSageString)?.timeIntervalSince1970 {
            let now = dateTimeUtils.getNowTimeIntervalUTC()
            let secondsAgo = now - sageTime
            
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .positional // Use the appropriate positioning for the current locale
            formatter.allowedUnits = [ .day, .hour] // Units to display in the formatted string
            formatter.zeroFormattingBehavior = [ .pad ] // Pad with zeroes where appropriate for the locale
            
            let formattedDuration = formatter.string(from: secondsAgo)
            tableData[6].value = formattedDuration ?? ""
        }
        infoTable.reloadData()
    }
    
    // NS Profile Web Call
    func webLoadNSProfile() {
        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Download: profile") }
        var urlString = UserDefaultsRepository.url.value + "/api/v1/profile/current.json"
        if token != "" {
            urlString += "?token=" + token
        }

        guard let url = URL(string: urlString) else {
            return
        }
        
        var request = URLRequest(url: url)
        request.cachePolicy = URLRequest.CachePolicy.reloadIgnoringLocalCacheData
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil else {
                return
            }
            guard let data = data else {
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? Dictionary<String, Any> {
                DispatchQueue.main.async {
                    self.updateProfile(jsonDeviceStatus: json)
                }
            } else {
                return
            }
        }
        task.resume()
    }
    
    // NS Profile Response Processor
    func calcBasalProfile(_ graphStart: TimeInterval, _ graphEnd : TimeInterval) -> [DataStructs.basalProfileSegment] {
        var basalSegments: [DataStructs.basalProfileSegment] = []

        // Build scheduled basal segments from right to left by
        // moving pointers to the current midnight and current basal
        var midnight = dateTimeUtils.getTimeIntervalMidnightToday()
        var basalProfileIndex = basalProfile.count - 1
        var start = midnight + basalProfile[basalProfileIndex].timeAsSeconds
        // Move back until we're in the graph range
        while start > graphEnd {
            basalProfileIndex -= 1
            start = midnight + basalProfile[basalProfileIndex].timeAsSeconds
        }
        // Add records while they're still within the graph
        var end = graphEnd
        while end >= graphStart {
            let entry = DataStructs.basalProfileSegment(basalRate: basalProfile[basalProfileIndex].value, startDate: start, endDate: end)
            basalSegments.append(entry)
            
            basalProfileIndex -= 1
            if basalProfileIndex < 0 {
                basalProfileIndex = basalProfile.count - 1
                midnight = midnight.advanced(by: -24*60*60)
            }
            end = start - 1
            start = midnight + basalProfile[basalProfileIndex].timeAsSeconds
        }
        // reverse the result to get chronological order
        basalSegments.reverse()

        return basalSegments
    }
    
    func updateProfile(jsonDeviceStatus: Dictionary<String, Any>) {
        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Process: profile") }
        if jsonDeviceStatus.count == 0 {
            return
        }
        if jsonDeviceStatus[keyPath: "message"] != nil { return }
        let basal = jsonDeviceStatus[keyPath: "store.Default.basal"] as! NSArray
        basalProfile.removeAll()
        for i in 0..<basal.count {
            let dict = basal[i] as! Dictionary<String, Any>
            let thisValue = dict[keyPath: "value"] as! Double
            let thisTime = dict[keyPath: "time"] as! String
            let thisTimeAsSeconds = dict[keyPath: "timeAsSeconds"] as! Double
            let entry = basalProfileStruct(value: thisValue, time: thisTime, timeAsSeconds: thisTimeAsSeconds)
            basalProfile.append(entry)
        }

        let graphHours = 24 * UserDefaultsRepository.downloadDays.value

        let timeStart = dateTimeUtils.getTimeIntervalNHoursAgo(N: graphHours)
        let predictionEndTime = dateTimeUtils.getNowTimeIntervalUTC() + (3600 * UserDefaultsRepository.predictionToLoad.value)
        let basalSegments = calcBasalProfile(timeStart, predictionEndTime)
        
        var firstPass = true
        // Runs the scheduled basal to the end of the prediction line
        basalScheduleData.removeAll()
        
        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Process: profile " + basalSegments.description) }

        for i in 0..<basalSegments.count {

            let segment = basalSegments[i]

            // we need to manually set the first one
            // Check that this is the first one and there are no existing entries
            if firstPass == true {
                // check that the timestamp is > the current entry and < the next entry
                if segment.startDate <= timeStart && timeStart < segment.endDate {

                    // Set the start time to match the BG start
                    let startDot = basalGraphStruct(basalRate: segment.basalRate, date: max(timeStart, segment.startDate))
                    basalScheduleData.append(startDot)

                    // set the enddot where the next one will start
                    let endDot = basalGraphStruct(basalRate: segment.basalRate, date: segment.endDate)
                    basalScheduleData.append(endDot)

                    firstPass = false
                }
                continue
            }

            // This processed everything after the first one.
            if segment.startDate <= predictionEndTime {
                let startDot = basalGraphStruct(basalRate: segment.basalRate, date: segment.startDate)
                basalScheduleData.append(startDot)

                let endDot = basalGraphStruct(basalRate: segment.basalRate, date: min(segment.endDate, predictionEndTime))
                basalScheduleData.append(endDot)
            }
        }
        
        if UserDefaultsRepository.graphBasal.value {
            updateBasalScheduledGraph()
        }
    }
    
    // NS Treatments Web Call
    // Downloads Basal, Bolus, Carbs, BG Check, Notes, Overrides
    func WebLoadNSTreatments() {
        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Download: Treatments") }
        if !UserDefaultsRepository.downloadTreatments.value { return }
        
        let graphHours = 24 * UserDefaultsRepository.downloadDays.value
        let startTimeString = dateTimeUtils.nowMinusNHoursTimeInterval(N: graphHours)
        
        var urlString = UserDefaultsRepository.url.value + "/api/v1/treatments.json?find[created_at][$gte]=" + startTimeString
        if token != "" {
            urlString += "&token=" + token
        }
        
        guard let urlData = URL(string: urlString) else {
            return
        }
        
        
        var request = URLRequest(url: urlData)
        request.cachePolicy = URLRequest.CachePolicy.reloadIgnoringLocalCacheData
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            
            guard error == nil else {
                return
            }
            guard let data = data else {
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data) as! [[String:AnyObject]]
                DispatchQueue.main.async {
                    self.updateTreatments(entries: json)
                }
            } catch {
                return
            }
        }
        task.resume()
    }
    
    // Process and split out treatments to individual tasks
    func updateTreatments(entries: [[String:AnyObject]]) {
        
        var tempBasal: [[String:AnyObject]] = []
        var bolus: [[String:AnyObject]] = []
        var carbs: [[String:AnyObject]] = []
        var temporaryOverride: [[String:AnyObject]] = []
        var note: [[String:AnyObject]] = []
        var bgCheck: [[String:AnyObject]] = []
        var suspendPump: [[String:AnyObject]] = []
        var resumePump: [[String:AnyObject]] = []
        var pumpSiteChange: [[String:AnyObject]] = []
        var cgmSensorStart: [[String:AnyObject]] = []
        
        for i in 0..<entries.count {
            let entry = entries[i] as [String : AnyObject]?
            switch entry?["eventType"] as! String {
                case "Temp Basal":
                    tempBasal.append(entry!)
                case "Correction Bolus":
                    bolus.append(entry!)
                case "Meal Bolus":
                    carbs.append(entry!)
                case "Carb Correction":
                    carbs.append(entry!)
                case "Temporary Override":
                    temporaryOverride.append(entry!)
                case "Note":
                    note.append(entry!)
                    print("Note: \(String(describing: entry))")
                case "BG Check":
                    bgCheck.append(entry!)
                case "Suspend Pump":
                    suspendPump.append(entry!)
                case "Resume Pump":
                    resumePump.append(entry!)
                case "Pump Site Change":
                    pumpSiteChange.append(entry!)
                case "Sensor Start":
                    cgmSensorStart.append(entry!)
                default:
                    print("No Match: \(String(describing: entry))")
            }
        }

        if tempBasal.count > 0 {
            processNSBasals(entries: tempBasal)
        } else if basalData.count < 0 {
            clearOldTempBasal()
        }
        
        if bolus.count > 0 {
            processNSBolus(entries: bolus)
        } else if bolusData.count > 0 {
            clearOldBolus()
        }
        
        if carbs.count > 0 {
            processNSCarbs(entries: carbs)
        } else if carbData.count > 0 {
            clearOldCarb()
        }
        
        if bgCheck.count > 0 {
            processNSBGCheck(entries: bgCheck)
        } else if bgCheckData.count > 0 {
            clearOldBGCheck()
        }

        if temporaryOverride.count > 0 {
            processNSOverrides(entries: temporaryOverride)
        } else if overrideGraphData.count > 0 {
            clearOldOverride()
        }

        if suspendPump.count > 0 {
            processSuspendPump(entries: suspendPump)
        } else if suspendGraphData.count > 0 {
            clearOldSuspend()
        }

        if resumePump.count > 0 {
            processResumePump(entries: resumePump)
        } else if resumeGraphData.count > 0 {
            clearOldResume()
        }

        if cgmSensorStart.count > 0 {
            processSensorStart(entries: cgmSensorStart)
        } else if sensorStartGraphData.count > 0 {
            clearOldSensor()
        }

        if note.count > 0 {
            processNotes(entries: note)
        } else if noteGraphData.count > 0 {
            clearOldNotes()
        }
    }
    
    func clearOldTempBasal() {
        basalData.removeAll()
        updateBasalGraph()
    }
    
    func clearOldBolus() {
        bolusData.removeAll()
        updateBolusGraph()
    }
    
    func clearOldCarb() {
        carbData.removeAll()
        updateCarbGraph()
    }
    
    func clearOldBGCheck() {
        bgCheckData.removeAll()
        updateBGCheckGraph()
    }
    
    func clearOldOverride() {
        overrideGraphData.removeAll()
        updateOverrideGraph()
    }
    
    func clearOldSuspend() {
        suspendGraphData.removeAll()
        updateSuspendGraph()
    }
    
    func clearOldResume() {
        resumeGraphData.removeAll()
        updateResumeGraph()
    }
    
    func clearOldSensor() {
        sensorStartGraphData.removeAll()
        updateSensorStart()
    }
    
    func clearOldNotes() {
        noteGraphData.removeAll()
        updateNotes()
    }
    
    // NS Temp Basal Response Processor
    func processNSBasals(entries: [[String:AnyObject]]) {
        self.clearLastInfoData(index: 2)
        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Process: Temp Basal") }
        // due to temp basal durations, we're going to destroy the array and load everything each cycle for the time being.
        basalData.removeAll()
        
        var lastEndDot = 0.0
        
        var tempArray = entries
        tempArray.reverse()
        for i in 0..<tempArray.count {
            guard let currentEntry = tempArray[i] as [String : AnyObject]? else { continue }
            guard let basalDate = getEntryDate(currentEntry: currentEntry) else { continue }
            let dateTimeStamp = dateTimeUtils.getNSTimeInterval(dateString: basalDate)

            guard let basalRate = currentEntry["absolute"] as? Double else {
                if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "ERROR: Null Basal entry")}
                continue
            }
            
            // Setting end dots
            let duration = currentEntry["duration"] as! Double
            
            // This adds scheduled basal wherever there is a break between temps. can't check the prior ending on the first item. it is 24 hours old, so it isn't important for display anyway
            if i > 0 {
                guard let priorEntry = tempArray[i - 1] as [String : AnyObject]? else { continue }

                guard let priorBasalDate = getEntryDate(currentEntry: priorEntry) else { continue }

                let priorDateTimeStamp = dateTimeUtils.getNSTimeInterval(dateString: priorBasalDate)
                
                let priorDuration = priorEntry["duration"] as! Double
                // if difference between time stamps is greater than the duration of the last entry, there is a gap. Give a 15 second leeway on the timestamp
                if Double( dateTimeStamp - priorDateTimeStamp ) > Double( (priorDuration * 60) + 15 ) {
                    
                    var scheduled = 0.0
                    let midGap = false
                    var midGapTime: TimeInterval = 0
                    var midGapValue: Double = 0
                    // cycle through basal profiles.
                    // TODO figure out how to deal with profile changes that happen mid-gap
                    for b in 0..<self.basalScheduleData.count {
                        if (priorDateTimeStamp + (priorDuration * 60)) >= basalScheduleData[b].date {
                            scheduled = basalScheduleData[b].basalRate
                            
                            // deal with mid-gap scheduled basal change
                            // don't do it on the last scheudled basal entry
                            if b < self.basalScheduleData.count - 1 {
                                if dateTimeStamp > self.basalScheduleData[b + 1].date {
                                   // midGap = true
                                    // TODO: finish this to handle mid-gap items without crashing from overlapping entries
                                    midGapTime = self.basalScheduleData[b + 1].date
                                    midGapValue = self.basalScheduleData[b + 1].basalRate
                                }
                            }
                        }
                    }

                    // Make the starting dot at the last ending dot
                    let startDot = basalGraphStruct(basalRate: scheduled, date: Double(priorDateTimeStamp + (priorDuration * 60)))
                    basalData.append(startDot)

                    if midGap {
                        // Make the ending dot at the new scheduled basal
                        let endDot1 = basalGraphStruct(basalRate: scheduled, date: Double(midGapTime))
                        basalData.append(endDot1)
                        // Make the starting dot at the scheduled Time
                        let startDot2 = basalGraphStruct(basalRate: midGapValue, date: Double(midGapTime))
                        basalData.append(startDot2)
                        // Make the ending dot at the new basal value
                        let endDot2 = basalGraphStruct(basalRate: midGapValue, date: Double(dateTimeStamp))
                        basalData.append(endDot2)
                        
                    } else {
                        // Make the ending dot at the new starting dot
                        let endDot = basalGraphStruct(basalRate: scheduled, date: Double(dateTimeStamp))
                        basalData.append(endDot)
                    }
                }
            }
            
            // Make the starting dot
            basalData.append(basalGraphStruct(basalRate: basalRate, date: Double(dateTimeStamp)))
            
            // Make the ending dot
            // If it's the last one and has no duration, extend it for 30 minutes past the start. Otherwise set ending at duration
            // duration is already set to 0 if there is no duration set on it.
            if i == tempArray.count - 1 && duration == 0.0 {
                lastEndDot = dateTimeStamp + (30 * 60)
                latestBasal = String(format:"%.2f U", basalRate)
            } else {
                lastEndDot = dateTimeStamp + (duration * 60)
                latestBasal = String(format:"%.2f U", basalRate)
            }
            
            // Double check for overlaps of incorrectly ended TBRs and sent it to end when the next one starts if it finds a discrepancy
            if i < tempArray.count - 1 {
                guard let nextEntry = tempArray[i + 1] as [String : AnyObject]? else { continue }
                guard let nextBasalDate = getEntryDate(currentEntry: nextEntry) else { continue }
                
                let nextDateTimeStamp = dateTimeUtils.getNSTimeInterval(dateString: nextBasalDate)
                
                if nextDateTimeStamp < (dateTimeStamp + (duration * 60)) {
                    lastEndDot = nextDateTimeStamp
                }
            }
            
            let endDot = basalGraphStruct(basalRate: basalRate, date: Double(lastEndDot))
            basalData.append(endDot)
        }
        
        // If last  basal was prior to right now, we need to create one last scheduled entry
        if lastEndDot <= dateTimeUtils.getNowTimeIntervalUTC() {
            var scheduled = 0.0
            // cycle through basal profiles.
            // TODO figure out how to deal with profile changes that happen mid-gap
            for b in 0..<self.basalProfile.count {
                let scheduleTimeYesterday = self.basalProfile[b].timeAsSeconds + dateTimeUtils.getTimeIntervalMidnightYesterday()
                let scheduleTimeToday = self.basalProfile[b].timeAsSeconds + dateTimeUtils.getTimeIntervalMidnightToday()
                // check the prior temp ending to the profile seconds from midnight
                print("yesterday " + String(scheduleTimeYesterday))
                print("today " + String(scheduleTimeToday))
                if lastEndDot >= scheduleTimeToday {
                    scheduled = basalProfile[b].value
                }
            }
            
            latestBasal = String(format:"%.2f U", scheduled)
            // Make the starting dot at the last ending dot
            let startDot = basalGraphStruct(basalRate: scheduled, date: Double(lastEndDot))
            basalData.append(startDot)
            
            // Make the ending dot 10 minutes after now
            let endDot = basalGraphStruct(basalRate: scheduled, date: Double(Date().timeIntervalSince1970 + (60 * 10)))
            basalData.append(endDot)
            
        }
        tableData[2].value = latestBasal
        infoTable.reloadData()
        if UserDefaultsRepository.graphBasal.value {
            updateBasalGraph()
        }
        infoTable.reloadData()
    }

    // NS Meal Bolus Response Processor
    func processNSBolus(entries: [[String:AnyObject]]) {
        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Process: Bolus") }
        // because it's a small array, we're going to destroy and reload every time.
        bolusData.removeAll()
        var lastFoundIndex = 0
        for currentEntry in entries.reversed() {

            guard let bolusDate = getEntryDate(currentEntry: currentEntry) else { continue }
            
            let dateTimeStamp = dateTimeUtils.getNSTimeInterval(dateString: bolusDate)

            guard let bolus = currentEntry["insulin"] as? Double else { continue }

            let sgv = findNearestBGbyTime(needle: dateTimeStamp, haystack: bgData, startingIndex: lastFoundIndex)
            lastFoundIndex = sgv.foundIndex
            
            if dateTimeStamp < (dateTimeUtils.getNowTimeIntervalUTC() + (60 * 60)) {
                // Make the dot
                let dot = bolusGraphStruct(value: bolus, date: Double(dateTimeStamp), sgv: Int(sgv.sgv + 20))
                bolusData.append(dot)
            }
        }
        
        if UserDefaultsRepository.graphBolus.value {
            updateBolusGraph()
        }
    }
   
    // NS Carb Bolus Response Processor
    func processNSCarbs(entries: [[String:AnyObject]]) {
        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Process: Carbs") }
        // because it's a small array, we're going to destroy and reload every time.
        carbData.removeAll()
        var lastFoundIndex = 0
        var lastFoundBolus = 0
        for currentEntry in entries.reversed() {

            guard let carbDate = getEntryDate(currentEntry: currentEntry) else { continue }

            let dateTimeStamp = dateTimeUtils.getNSTimeInterval(dateString: carbDate)

            let absorptionTime = currentEntry["absorptionTime"] as? Int ?? 0
            guard let carbs = currentEntry["carbs"] as? Double else {
                if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "ERROR: Null Carb entry")}
                continue
            }
            let sgv = findNearestBGbyTime(needle: dateTimeStamp, haystack: bgData, startingIndex: lastFoundIndex)
            lastFoundIndex = sgv.foundIndex

            var offset = -50
            if sgv.sgv < Double(topBG - 100) {
                let bolusTime = findNearestBolusbyTime(timeWithin: 300, needle: dateTimeStamp, haystack: bolusData, startingIndex: lastFoundBolus)
                lastFoundBolus = bolusTime.foundIndex

                if bolusTime.offset {
                    offset = 70
                } else {
                    offset = 20
                }
            }

            if dateTimeStamp < (dateTimeUtils.getNowTimeIntervalUTC() + (60 * 60)) {
                let dot = carbGraphStruct(
                    value: Double(carbs),
                    date: dateTimeStamp,
                    sgv: Int(sgv.sgv + Double(offset)),
                    absorptionTime: absorptionTime
                )
                carbData.append(dot)
            }
        }
        
        if UserDefaultsRepository.graphCarbs.value {
            updateCarbGraph()
        }
    }
    
    // NS Suspend Pump Response Processor
    func processSuspendPump(entries: [[String:AnyObject]]) {
        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Process: Suspend Pump") }
        // because it's a small array, we're going to destroy and reload every time.
        suspendGraphData.removeAll()
        var lastFoundIndex = 0
        for currentEntry in entries.reversed() {

            guard let dateString = getEntryDate(currentEntry: currentEntry) else { continue }
            let dateTimeStamp = dateTimeUtils.getNSTimeInterval(dateString: dateString)

            let sgv = findNearestBGbyTime(needle: dateTimeStamp, haystack: bgData, startingIndex: lastFoundIndex)
            lastFoundIndex = sgv.foundIndex
            
            if dateTimeStamp < (dateTimeUtils.getNowTimeIntervalUTC() + (60 * 60)) {
                // Make the dot
                let dot = DataStructs.timestampOnlyStruct(date: Double(dateTimeStamp), sgv: Int(sgv.sgv))
                suspendGraphData.append(dot)
            }
        }

        if UserDefaultsRepository.graphOtherTreatments.value {
            updateSuspendGraph()
        }
    }
    
    // NS Resume Pump Response Processor
    func processResumePump(entries: [[String:AnyObject]]) {
        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Process: Resume Pump") }
        // because it's a small array, we're going to destroy and reload every time.
        resumeGraphData.removeAll()
        var lastFoundIndex = 0
        for currentEntry in entries.reversed() {
        
            guard let dateString = getEntryDate(currentEntry: currentEntry) else { continue }
            let dateTimeStamp = dateTimeUtils.getNSTimeInterval(dateString: dateString)

            let sgv = findNearestBGbyTime(needle: dateTimeStamp, haystack: bgData, startingIndex: lastFoundIndex)
            lastFoundIndex = sgv.foundIndex
            
            if dateTimeStamp < (dateTimeUtils.getNowTimeIntervalUTC() + (60 * 60)) {
                // Make the dot
                let dot = DataStructs.timestampOnlyStruct(date: Double(dateTimeStamp), sgv: Int(sgv.sgv))
                resumeGraphData.append(dot)
            }
        }

        if UserDefaultsRepository.graphOtherTreatments.value {
            updateResumeGraph()
        }
    }
    
    // NS Sensor Start Response Processor
    func processSensorStart(entries: [[String:AnyObject]]) {
        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Process: Sensor Start") }
        // because it's a small array, we're going to destroy and reload every time.
        sensorStartGraphData.removeAll()
        var lastFoundIndex = 0
        for currentEntry in entries.reversed() {

            guard let dateString = getEntryDate(currentEntry: currentEntry) else { continue }
            let dateTimeStamp = dateTimeUtils.getNSTimeInterval(dateString: dateString)

            let sgv = findNearestBGbyTime(needle: dateTimeStamp, haystack: bgData, startingIndex: lastFoundIndex)
            lastFoundIndex = sgv.foundIndex
            
            if dateTimeStamp < (dateTimeUtils.getNowTimeIntervalUTC() + (60 * 60)) {
                // Make the dot
                let dot = DataStructs.timestampOnlyStruct(date: Double(dateTimeStamp), sgv: Int(sgv.sgv))
                sensorStartGraphData.append(dot)
            }
        }

        if UserDefaultsRepository.graphOtherTreatments.value {
            updateSensorStart()
        }
    }
    
    // NS Note Response Processor
    func processNotes(entries: [[String:AnyObject]]) {
        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Process: Notes") }
        // because it's a small array, we're going to destroy and reload every time.
        noteGraphData.removeAll()
        var lastFoundIndex = 0
        for currentEntry in entries.reversed() {

            guard let dateString = getEntryDate(currentEntry: currentEntry) else { continue }
            let dateTimeStamp = dateTimeUtils.getNSTimeInterval(dateString: dateString)

            let sgv = findNearestBGbyTime(needle: dateTimeStamp, haystack: bgData, startingIndex: lastFoundIndex)
            lastFoundIndex = sgv.foundIndex
            
            guard let thisNote = currentEntry["notes"] as? String else { continue }
            
            if dateTimeStamp < (dateTimeUtils.getNowTimeIntervalUTC() + (60 * 60)) {
                // Make the dot
                let dot = DataStructs.noteStruct(date: Double(dateTimeStamp), sgv: Int(sgv.sgv), note: thisNote)
                noteGraphData.append(dot)
            }
        }
        if UserDefaultsRepository.graphOtherTreatments.value {
            updateNotes()
        }
    }
    
    // NS BG Check Response Processor
    func processNSBGCheck(entries: [[String:AnyObject]]) {
        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Process: BG Check") }
        // because it's a small array, we're going to destroy and reload every time.
        bgCheckData.removeAll()
        for currentEntry in entries.reversed() {

            guard let dateString = getEntryDate(currentEntry: currentEntry) else { continue }
            let dateTimeStamp = dateTimeUtils.getNSTimeInterval(dateString: dateString)
            
            guard let sgv = currentEntry["glucose"] as? Int else {
                if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "ERROR: Non-Int Glucose entry")}
                continue
            }
            
            if dateTimeStamp < (dateTimeUtils.getNowTimeIntervalUTC() + (60 * 60)) {
                // Make the dot
                //let dot = ShareGlucoseData(value: Double(carbs), date: Double(dateTimeStamp), sgv: Int(sgv.sgv))
                let dot = ShareGlucoseData(sgv: sgv, date: Double(dateTimeStamp), direction: "")
                bgCheckData.append(dot)
            }
        }

        if UserDefaultsRepository.graphOtherTreatments.value {
            updateBGCheckGraph()
        }
    }
    
    // NS Override Response Processor
    func processNSOverrides(entries: [[String:AnyObject]]) {
        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Process: Overrides") }
        // because it's a small array, we're going to destroy and reload every time.
        overrideGraphData.removeAll()

        let startOfGraph = dateTimeUtils.getTimeIntervalNHoursAgo(N: 24 * UserDefaultsRepository.downloadDays.value)
        let endOfGraph = dateTimeUtils.getTimeIntervalNHoursAgo(N: -Int(UserDefaultsRepository.predictionToLoad.value))

        for currentEntry in entries.reversed() {
            guard let dateValue = getEntryDate(currentEntry: currentEntry) else { continue }

            let dateTimeStamp = max(dateTimeUtils.getNSTimeInterval(dateString: dateValue), startOfGraph)
            
            var multiplier: Double = 1.0
            if currentEntry["insulinNeedsScaleFactor"] != nil {
                multiplier = currentEntry["insulinNeedsScaleFactor"] as! Double
            }
            var duration: Double = 5.0
            if currentEntry["durationType"] is String {
                duration = dateTimeUtils.getNowTimeIntervalUTC() - dateTimeStamp + (60 * 60)
            } else {
                duration = (currentEntry["duration"] as? Double)! * 60
            }

            // Skip overrides that aren't 5 minutes long. This prevents overlapping that causes bars to not display.
            if duration < 300 {
                continue
            }
            
            guard let enteredBy = currentEntry["enteredBy"] as? String else { continue }
            guard let reason = currentEntry["reason"] as? String else { continue }
            
            var range: [Int] = []
            if let ranges = currentEntry["correctionRange"] as? [Int] {
                if ranges.count == 2 {
                    range.append(ranges[0])
                    range.append(ranges[1])
                }
            }
                        
            let endDate = min(dateTimeStamp + duration, endOfGraph)
            let dot = DataStructs.overrideStruct(
                    insulNeedsScaleFactor: multiplier,
                    date: dateTimeStamp,
                    endDate: endDate,
                    duration: duration,
                    correctionRange: range,
                    enteredBy: enteredBy,
                    reason: reason,
                    sgv: -20)

            overrideGraphData.append(dot)
        }

        if UserDefaultsRepository.graphOtherTreatments.value {
            updateOverrideGraph()
        }
    }

    func getEntryDate(currentEntry : [String:AnyObject]) -> String? {
        if currentEntry["timestamp"] != nil {
            return currentEntry["timestamp"] as! String?
        }

        if currentEntry["created_at"] != nil {
            return currentEntry["created_at"] as! String?
        }

        return nil
    }
}
