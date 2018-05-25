// Weather Monitor
// Copyright 2016-18, Tony Smith

// IMPORTS
#require "DarkSky.class.nut:1.0.1"
#require "Rocky.class.nut:2.0.1"
#require "IFTTT.class.nut:1.0.0"
#import "../Location/location.class.nut"

// CONSTANTS
const REFRESH_TIME = 900;
const AGENT_START_TIME = 120;
// If you are NOT using Squinter or a similar tool, replace the #import statement below
// with the contents of the named file (matrixclock_ui.html)
const HTML_STRING = @"
#import "weather_ui.html"
";

// GLOBAL VARIABlES
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

local myLongitude = -0.123038;
local myLatitude = 51.568330;
local myLocation = "London, UK";
local locationTime = -1;

local deviceSyncFlag = false;
local debug = false;
local clearSettings = false;

// FORECAST FUNCTIONS
function sendForecast(dummy) {
   if (debug) server.log("Requesting weather forecast data from Dark Sky");
    weather.forecastRequest(myLongitude, myLatitude, forecastCallback.bindenv(this));
}

function forecastCallback(err, data) {
    if (debug) {
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
                if (debug) server.log("Sending data to device");
                device.send("weather.show.forecast", sendData);
                savedData = sendData;
            }
        }

        if ("callCount" in data) {
            // Send an event to IFTTT to trigger a warning email, if necessary
            if (data.callCount > 950) mailer.sendEvent("darksky_warning", [data.callCount, "out of", 1000]);
            if (debug) server.log("Current Dark Sky API call tally: " + data.callCount + "/1000");
        }
    }

    // Get the indoors temperature from the sensor agent
    // This only works if you have set up an Environment Tail Sensor,
    // see https://github.com/smittytone/EnvTailTempLog
    http.get(sensorAgentURL + "/state").sendasync(function(response) {
        if (response.statuscode == 200) {
            if ("body" in response) {
                try {
                    if (debug) server.log("Inside temperature data received from remote sensor");
                    local data = http.jsondecode(response.body);
                    device.send("weather.set.local.temp", data.temp);
                } catch (error) {
                    if (debug) server.error("Could not decode JSON from agent");
                }
            }
        } else {
            if (response.statuscode == 404) {
                if (debug) server.log("Remote sensor not available");
            } else {
                if (debug) server.error("Response from sensor agent: " + response.statuscode + " - " + response.body);
            }
        }
    });

    // Tell the agent get the next forecast in 'REFRESH_TIME' seconds time
    if (weatherTimer) imp.cancelwakeup(weatherTimer);
    weatherTimer = imp.wakeup(REFRESH_TIME, function(){
        sendForecast(true);
    });
}

// LOCATION FUNCTIONS
function locationLookup(dummy) {
    if (restartTimer) imp.cancelwakeup(restartTimer);
    restartTimer = null;

    if ((locationTime != -1) && (time() - locationTime < 86400)) {
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
            sendForecast(true);

            if (debug) {
                server.log("Co-ordinates: " + myLongitude + ", " + myLatitude);
                server.log("Location    : " + myLocation);
            }

            local tz = locator.getTimezone();
            if (!("error" in tz) && debug) server.log("Timezone    : " + tz.gmtOffsetStr);
        } else {
            server.error(locale.err);
            imp.wakeup(10, function() {
                locationLookup(true);
            });
        }
    });

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

// SETTINGS FUNCTIONS
function getSettings(dummy) {
    device.send("weather.set.settings", settings);
}

function reset() {
    if (debug) server.log("Clearing settings to default values");
    server.save({});
    settings = {};
    settings.angle <- 0;
    settings.bright <- 15;
    settings.debug <- false;
    server.save(settings);
}

// START PROGRAM

// If you are NOT using Squinter, uncomment the following lines and add your API keys...
// weather = DarkSky("YOUR_API_KEY");
// locator = Location("YOUR_GOOGLE_API_KEY(s)", debug);
// mailer = IFTTT("YOUR_APPLET_ID");
// agent = "YOUR ENV TAIL AGENT URL";
// const APP_CODE = "Weather";

#import "~/Dropbox/Programming/Imp/Codes/weather.nut"

// Specify UK units for all forecasts, ie. temperatures in Celsius
weather.setUnits("uk");

// Set up settings record
local loadedSettings = server.load();

if (loadedSettings.len() == 0) {
    // No saved data, so save defaults
    settings = {};
    settings.angle <- 0;
    settings.bright <- 15;
    settings.debug <- false;
    server.save(settings);
} else {
    // Clear settings if required (but only if we HAVE saved settings)
    if (clearSettings) {
        reset();
    } else {
        settings = loadedSettings;
        if ("debug" in settings) {
            debug = settings.debug;
        } else {
            settings.debug <- debug;
        }
    }
}

// Register the function to call when the device asks for a forecast
device.on("weather.get.location", locationLookup);
device.on("weather.get.forecast", sendForecast);
device.on("weather.get.settings", getSettings);

// Set up the API that the agent will server
api = Rocky();

// GET at / returns the UI
api.get("/", function(context) {
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
    data.bright <- settings.bright;
    data.debug <- settings.debug;
    data = http.jsonencode(data);
    context.send(200, data);
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
                if (debug) server.log("Restarting Device");
                device.send("weather.set.reboot", true);
            } else if (data.action == "reset") {
                // Clear and reset the settings, then
                // reboot the device to apply them
                reset();
                if (debug) server.log("Restarting Device");
                device.send("weather.set.reboot", true);
            }
        }
    } catch (err) {
        server.error(err);
        context.send(400, "Bad data posted");
        return;
    }

    context.send(200, "OK");
});

// POST at /settings updates the passed setting(s)
// passed to the endpoint:
// { "angle" : <0-270>,
//   "bright" : <0-15>  }
api.post("/settings", function(context) {
    try {
        local data = http.jsondecode(context.req.rawbody);
        if ("angle" in data) {
            local a = data.angle.tointeger();
            if (debug) server.log("Display angle changed to " + a);
            device.send("weather.set.angle", a);
            settings.angle = a;
        }

        if ("bright" in data) {
            local b = data.bright.tointeger();
            if (debug) server.log("Display brightness changed to " + b);
            device.send("weather.set.bright", b);
            settings.bright = b;
        }
    } catch (err) {
        server.error(err);
        context.send(400, "Bad data posted");
        return;
    }

    context.send(200, "OK");
    local r = server.save(settings);
    if (r != 0) server.error("Could not save settings (code: " + r + ")");
});

// POST at /debug updates the passed setting(s)
// passed to the endpoint:
// { "debug" : <true/false> }
api.post("/debug", function(context) {
    try {
        local data = http.jsondecode(context.req.rawbody);
        if ("debug" in data) {
            debug = data.debug;
            if (debug) {
                server.log("Debug enabled");
            } else {
                server.log("Debug disabled");
            }

            device.send("weather.set.debug", debug);
            settings.debug = debug;
            local r = server.save(settings);
            if (r != 0) server.error("Could not save settings (code: " + r + ")");
        }
    } catch (err) {
        server.error(err);
        context.send(400, "Bad data posted");
        return;
    }

    context.send(200, (debug ? "Debug on" : "Debug off"));
});

// GET at /controller/info returns app data for Controller
api.get("/controller/info", function(context) {
    local info = { "appcode": APP_CODE,
                   "watchsupported": "true" };
    context.send(200, http.jsonencode(info));
});

// GET at /controller/state returns device status for Controller
api.get("/controller/state", function(context) {
    local data = device.isconnected() ? "1" : "0";
    context.send(200, data);
});

// In 'AGENT_START_TIME' seconds, check if the device has not synced (as far as
// the agent knows) and is connected, ie. we have probably experienced
// an unexpected agent restart. If so, do a location lookup as if asked
// by a newly starting device
restartTimer = imp.wakeup(AGENT_START_TIME, function() {
    if (!deviceSyncFlag) {
        if (device.isconnected()) {
            if (debug) server.log("Reacquiring location due to agent restart");
            locationLookup(true);
        } else {
            if (debug) server.log("Agent restarted, but device not online");
        }
    }
});
