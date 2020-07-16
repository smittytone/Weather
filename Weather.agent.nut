// Weather Monitor
// Copyright 2020, Tony Smith

// ********** IMPORTS **********
#require "DarkSky.agent.lib.nut:2.0.0"
#require "Rocky.agent.lib.nut:3.0.0"
#require "IFTTT.class.nut:1.0.0"

// If you are NOT using Squinter or a similar tool, replace the following #import statement(s)
// with the contents of the named file(s):
#import "../generic-squirrel/simpleslack.nut"           // Source code: https://github.com/smittytone/generic-squirrel
#import "../generic-squirrel/crashReporter.nut"         // Source code: https://github.com/smittytone/generic-squirrel
#import "../Location/location.class.nut"                // Source file in https://github.com/smittytone/Location
const HTML_STRING = @"
#import "weather_ui.html"
";                                                  // Source file in https://github.com/smittytone/Weather

// ********** CONSTANTS **********
const FORECAST_REFRESH_INTERVAL = 900;  // 15 minutes
const AGENT_START_TIME = 120;


// ********** GLOBAL VARIABlES **********
local request = null;
local weather = null;
local locator = null;
local mailer = null;
local sensorAgentURL = null
local weatherTimer = null;
local restartTimer = null;
local settings = null;
local api = null;
local savedData = null;

local myLongitude = -1;
local myLatitude = -1;
local myLocation = "Unknown";
local locationTime = -1;
local darkSkyCount = 0;

local deviceSyncFlag = false;


// ********** FORECAST FUNCTIONS **********
function sendForecast(dummy) {
    // Request a weather forecast, but only if there are less than 1000 previous requests today
    // NOTE the count is maintined by DarkSky; we reload it every time
    if (darkSkyCount < 990) {
        if (settings.debug) server.log("Requesting weather forecast data from Dark Sky");
        weather.forecastRequest(myLongitude, myLatitude, forecastCallback.bindenv(this));
    }
}

function forecastCallback(err, data) {
    if (settings.debug) {
        if (err) server.error(err);
        if (data) server.log("Weather forecast data received from Dark Sky");
    }

    if (data) {
        if ("hourly" in data) {
            if ("data" in data.hourly) {
                // Get second item in array: this is the weather one hour from now
                local item = data.hourly.data[1];
                local sendData = {};
                sendData.cast <- item.icon;

                // Adjust troublesome icon names
                if (item.icon == "wind") sendData.cast = "windy";
                if (item.icon == "fog") sendData.cast = "foggy";

                if (item.icon == "clear-day") {
                    item.icon = "clearday";
                    sendData.cast = "clear";
                }

                if (item.icon == "clear-night") {
                    item.icon = "clearnight";
                    sendData.cast = "clear";
                }

                if (item.icon == "partly-cloudy-day" || item.icon == "partly-cloudy-night") {
                    item.icon = "partlycloudy";
                    sendData.cast = "partly cloudy";
                }

                if (item.summary == "Drizzle" || item.summary == "Light Rain") {
                    item.icon = "lightrain";
                    sendData.cast = "drizzle";
                }

                local initial = sendData.cast.slice(0, 1);
                sendData.cast = initial.toupper() + sendData.cast.slice(1);

                // Send the icon name to the device
                sendData.icon <- item.icon;
                sendData.temp <- item.apparentTemperature;
                if (settings.debug) server.log("Sending data to device");
                device.send("weather.show.forecast", sendData);
                savedData = sendData;
            }
        }

        if ("callCount" in data) {
            // Send an event to IFTTT to trigger a warning email, if necessary
            if (data.callCount > 950) mailer.sendEvent("darksky_warning", [data.callCount, "out of", 1000]);
            if (settings.debug) server.log("Current Dark Sky API call tally: " + data.callCount + "/1000");
            darkSkyCount = data.callCount;
        }
    }

    // Get the indoors temperature from the sensor agent
    // This only works if you have set up an Environment Tail Sensor,
    // see https://github.com/smittytone/EnvTailTempLog
    http.get(sensorAgentURL + "/state").sendasync(function(response) {
        if (response.statuscode == 200) {
            if ("body" in response) {
                try {
                    if (settings.debug) server.log("Inside temperature data received from remote sensor");
                    local data = http.jsondecode(response.body);
                    device.send("weather.set.local.temp", data.temp.tofloat());
                } catch (error) {
                    if (settings.debug) server.error("Could not decode JSON from agent");
                }
            }
        } else {
            if (response.statuscode == 404) {
                if (settings.debug) server.log("Remote sensor not available");
            } else {
                if (settings.debug) server.error("Response from sensor agent: " + response.statuscode + " - " + response.body);
            }
        }
    });

    // Tell the agent get the next forecast in 'FORECAST_REFRESH_INTERVAL' seconds time
    if (weatherTimer) imp.cancelwakeup(weatherTimer);
    weatherTimer = imp.wakeup(FORECAST_REFRESH_INTERVAL, function(){
        sendForecast(true);
    });
}


// ********** LOCATION FUNCTIONS **********
function locationLookup(dummy) {
    // Now we've received a message from the device, if the agent restart timer is
    // running, kill it
    if (restartTimer) {
        imp.cancelwakeup(restartTimer);
        restartTimer = null;
    }

    // Kill the weather forecast timer
    if (weatherTimer) {
        imp.cancelwakeup(weatherTimer);
        weatherTimer = null;
    }

    if (locationTime != -1) {
        // No need to check within one day of locating the device
        sendForecast(true);
        return;
    }

    locator.locate(false, function() {
        local locale = locator.getLocation();
        if (!("error" in locale)) {
            myLongitude = locale.longitude;
            myLatitude = locale.latitude;
            myLocation = parsePlaceData(locale.placeData);
            locationTime = time();

            // FROM 3.12.0
            // Save the location to minimize lookups
            settings.loc <- { "tim": locationTime,
                              "plc": myLocation,
                              "lon": myLongitude,
                              "lat": myLatitude};
            server.save(settings);

            if (settings.debug) {
                server.log("Co-ordinates: " + myLongitude + ", " + myLatitude);
                server.log("Location    : " + myLocation);
            }

            local tz = locator.getTimezone();
            if (!("error" in tz) && settings.debug) server.log("Timezone    : " + tz.gmtOffsetStr);

            sendForecast(true);
        } else {
            server.error(locale.err);
            imp.wakeup(10, function() {
                locationLookup(true);
            });
        }
    });

    // Mark device as connected, since its arrival initiated this call
    deviceSyncFlag = true;
}

function parsePlaceData(data) {
    // Run through the raw place data returned by Google and find what area we're in
    foreach (item in data) {
        foreach (k, v in item) {
            // We're looking for the 'types' array
            if (k == "types") {
                // Got it, so look through the elements for 'neighborhood'
                foreach (entry in v) {
                    if (entry == "neighborhood") return item.formatted_address;
                }

                // No 'neighborhood'? Try 'locality'
                foreach (entry in v) {
                    if (entry == "locality") return item.formatted_address;
                }

                // No 'locality'? Try 'administrative_area_level_2'
                foreach (entry in v) {
                    if (entry == "administrative_area_level_2") return item.formatted_address;
                }

                // No 'administrative_area_level_2'? Try 'dministrative_area_level_3'
                foreach (entry in v) {
                    if (entry == "administrative_area_level_3") return item.formatted_address;
                }
            }
        }
    }

    // No match, so return an unknown locality
    return "Unknown";
}


// ********** SETTINGS FUNCTIONS **********
function initialiseSettings() {
    // Reset the application settings and re-save them
    settings = {};
    settings.angle <- 0;
    settings.bright <- 5;
    settings.debug <- false;
    settings.power <- true;
    settings.repeat <- false;
    settings.period <- 15;
    settings.inverse <- false;
    settings.loc <- { "tim": locationTime,
                      "plc": myLocation,
                      "lon": myLongitude,
                      "lat": myLatitude};
    server.save(settings);
    if (settings.debug) server.log("Clearing settings to default values");

}


// ********** LOGGING FUNCTIONS **********
function debugAPI(context, next) {
    // Display a UI API activity report
    if (settings.debug) {
        server.log("API received a request at " + time() + ": " + context.req.method.toupper() + " @ " + context.req.path.tolower());
        if (context.req.rawbody.len() > 0) server.log("Request body: " + context.req.rawbody.tolower());
    }

    // Invoke the next middleware
    next();
}


// ********** RUNTIME START **********

// If you are NOT using Squinter, uncomment the following lines and add your API keys...
// weather = DarkSky("YOUR_API_KEY");
// locator = Location("YOUR_GOOGLE_API_KEY(s)", settings.debug);
// mailer = IFTTT("YOUR_APPLET_ID");
// agent = "YOUR ENV TAIL AGENT URL";
// const APP_CODE = "Weather";
#import "~/OneDrive/Programming/Weather/weather.nut"

// Specify UK units for all forecasts, ie. temperatures in Celsius
weather.setUnits("uk");

// Set up settings record
local loadedSettings = server.load();

if (loadedSettings.len() == 0) {
    // No saved data, so save defaults
    initialiseSettings();
} else {
    // Clear settings if required (but only if we HAVE saved settings)
    settings = loadedSettings;
    local doSave = false;

    // Handle later additions to the settings
    if (!("debug" in settings)) {
        settings.debug <- false;
        doSave = true;
    }
    if (!("period" in settings)) {
        settings.period <- 15;
        doSave = true;
    }

    if (!("power" in settings)) {
        settings.power <- true;
        doSave = true;
    }

    if (!("repeat" in settings)) {
        settings.repeat <- false;
        doSave = true;
    }

    if (!("inverse" in settings)) {
        settings.inverse <- false;
        doSave = true;
    }

    if (!("loc" in settings)) {
        settings.loc <- { "tim": locationTime,
                          "plc": myLocation,
                          "lon": myLongitude,
                          "lat": myLatitude};
        doSave = true;
    } else {
        // FROM 3.12.0
        // Set location
        myLongitude = settings.loc.lon;
        myLatitude = settings.loc.lat;
        myLocation = settings.loc.plc;
        locationTime = settings.loc.tim;
    }

    if (doSave) server.save(settings);
}

// Register the function to call when the device asks for a forecast
device.on("weather.get.location", locationLookup);
//device.on("weather.get.forecast", sendForecast);
device.on("weather.get.settings", function(dummy) {
    device.send("weather.set.settings", settings);
    if (settings.debug) server.log(http.jsonencode(settings, {"compact":true}));
});

// Set up the API that the agent will server
api = Rocky.init();
api.use(debugAPI);

// Set up UI access security: HTTPS only
api.authorize(function(context) {
    // Mandate HTTPS connections
    if (context.getHeader("x-forwarded-proto") != "https") return false;
    return true;
});

api.onUnauthorized(function(context) {
    // Incorrect level of access security
    context.send(401, "Insecure access forbidden");
});

// GET at / returns the UI via a redirect to 'index.html'
api.get("/", function(context) {
    context.setHeader("Location", http.agenturl() + "/index.html");
    context.send(301);
});

api.get("/index.html", function(context) {
    context.send(200, format(HTML_STRING, http.agenturl()));
});

// GET at /current returns the current forecast as JSON:
// { "cast" : "<the forecast>",
//   "icon" : "<the weather icon name>" }
// If there is an error, the JSON will contain the key 'error'
api.get("/current", function(context) {
    local data = {};

    if (savedData != null) {
        data = savedData;
    } else {
        data.error <- "Weather data not yet received. Please try again shortly";
    }

    local loc = {};
    loc.long <- myLongitude;
    loc.lat <- myLatitude;
    loc.place <- myLocation;
    data.location <- loc;
    data.angle <- settings.angle.tostring();
    data.bright <- settings.bright;     // Brightness in UI is 1-16
    data.debug <- settings.debug;
    data.power <- settings.power;
    data.repeat <- settings.repeat;
    data.period <- settings.period;
    data.inverse <- settings.inverse;

    context.send(200, http.jsonencode(data));
});

// POST at /update triggers an action, chosen by the JSON
// passed to the endpoint:
// { "action" : "<update/reboot>" }
// 'update' causes the forecast to be updated
// 'reboot' causes the device to restart
api.post("/update", function(context) {
    try {
        local data = http.jsondecode(context.req.rawbody);
        if ("action" in data) {
            if (data.action == "update") {
                sendForecast(true);
            } else if (data.action == "reboot") {
                if (settings.debug) server.log("Restarting device via UI");
                initialiseSettings();
                device.send("weather.set.reboot", true);
            } else if (data.action == "power") {
                if (settings.debug) server.log("Switching display power via UI");
                settings.power = !settings.power;
                device.send("weather.set.power", settings.power);
            } else if (data.action == "reset") {
                // Clear and reset the settings, then
                // reboot the device to apply them
                initialiseSettings();
                if (settings.debug) server.log("Restarting device via UI");
                device.send("weather.set.reboot", true);
            } else if (data.action == "locate") {
                if (settings.debug) server.log("Relocating device");
                locationTime = -1;
                locationLookup(true);
            }
        } else {
            context.send(400, "Bad command posted by UI to /update");
            return;
        }
    } catch (err) {
        server.error(err);
        context.send(400, "Bad data posted by UI to /update");
        return;
    }

    context.send(200, "OK");
});

// POST at /settings updates the passed setting(s)
// passed to the endpoint:
// { "angle"  : <0-270>,
//   "bright" : <0-15>,
//   "power"  : <true/false>,
//   "repeat" : <true/false>,
//   "video"  : <true/false> }
api.post("/settings", function(context) {
    try {
        local data = http.jsondecode(context.req.rawbody);

        if ("angle" in data) {
            local a = data.angle.tointeger();
            if (settings.debug) server.log("Display angle changed by UI to " + a);
            device.send("weather.set.angle", a);
            settings.angle = a;
        }

        if ("bright" in data) {
            local b = data.bright.tointeger();
            if (settings.debug) server.log("Display brightness changed by UI to " + b);
            device.send("weather.set.bright", b);
            settings.bright = b;
        }

        if ("power" in data) {
            local p = data.power;
            if (settings.debug) server.log("Display turned " + (p ? "on" : "off") + " by UI");
            device.send("weather.set.power", p);
            settings.power = p;
        }

        if ("repeat" in data) {
            local r = data.repeat;
            if (settings.debug) server.log("Repeat mode " + (r ? "en" : "dis") + "abled by UI");
            device.send("weather.set.repeat", r);
            settings.repeat = r;
        }

        if ("period" in data) {
            local p = data.period.tointeger();
            if (settings.debug) server.log("Repeat period set to " + p);
            device.send("weather.set.period", p);
            settings.period = p;
        }

        if ("video" in data) {
            local i = data.video;
            if (settings.debug) server.log("LED set to " + (i ? "black on green" : "green on black") + " by UI");
            device.send("weather.set.video", i);
            settings.inverse = i;
        }
    } catch (err) {
        server.error(err);
        context.send(400, "Bad data posted by UI to /settings");
        return;
    }

    context.send(200, "OK");
    server.save(settings);
});

// POST at /debug updates the passed setting(s)
// passed to the endpoint:
// { "debug" : <true/false> }
api.post("/debug", function(context) {
    try {
        local data = http.jsondecode(context.req.rawbody);
        if ("debug" in data) {
            settings.debug = data.debug;
            server.log("Debug " + (settings.debug ? "enabled" : "disabled") + " by UI");
            device.send("weather.set.debug", settings.debug);
            server.save(settings);
        } else {
            context.send(400, "Bad command posted by UI to /debug");
            return;
        }
    } catch (err) {
        server.error(err);
        context.send(400, "Bad data posted by UI to /debug");
        return;
    }

    context.send(200, (settings.debug ? "Debug on" : "Debug off"));
});

// GET at /controller/info returns app data for Controller
api.get("/controller/info", function(context) {
    local info = { "appcode": APP_CODE,
                   "watchsupported": "true" };
    context.send(200, http.jsonencode(info));
});

// GET at /controller/state returns device status for Controller
api.get("/controller/state", function(context) {
    // Sends a status string, eg. "0.1"
    // First digit it 1/0 (true/false) for display is connected
    // Second digit it 1/0 (true/false) for display is powered
    local data = { "isconnected" : device.isconnected(),
                   "ispowered" : settings.power };
    context.send(200, http.jsonencode(data));
});

// In 'AGENT_START_TIME' seconds, check if the device has not synced (as far as
// the agent knows) and is connected, ie. we have probably experienced
// an unexpected agent restart. If so, do a location lookup as if asked
// by a newly starting device
restartTimer = imp.wakeup(AGENT_START_TIME, function() {
    if (!deviceSyncFlag) {
        if (device.isconnected()) {
            if (settings.debug) server.log("Reacquiring location due to agent restart");
            locationLookup(true);
        } else {
            if (settings.debug) server.log("Agent restarted, but device not online");
        }
    }
});
