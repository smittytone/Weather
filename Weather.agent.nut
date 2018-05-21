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
const HTML_STRING = @"<!DOCTYPE html><html lang='en-US'><meta charset='UTF-8'>
<html>
    <head>
        <title>Weather Monitor</title>
        <link rel='stylesheet' href='https://netdna.bootstrapcdn.com/bootstrap/3.1.1/css/bootstrap.min.css'>
        <link href='https://fonts.googleapis.com/css?family=Abel' rel='stylesheet'>
        <link rel='apple-touch-icon' href='https://smittytone.github.io/images/ati-weather.png'>
        <link rel='shortcut icon' href='https://smittytone.github.io/images/ico-weather.ico'>
        <meta name='viewport' content='width=device-width, initial-scale=1.0'>
        <style>
            .center { margin-left: auto;
                      margin-right: auto;
                      margin-bottom: auto;
                      margin-top: auto; }
            .showhide { -webkit-touch-callout: none;
                        -webkit-user-select: none;
                        -khtml-user-select: none;
                        -moz-user-select: none;
                        -ms-user-select: none;
                        user-select: none;
                        cursor: pointer }
            body { background-color: #b30000; }
            p {color: white; font-family: Abel, sans-serif; font-size: 18px}
            p.error-message {color:#ffcc00; font-size: 16px}
            p.colophon {font-size: 14px; text-align: center}
            h2 {color: #ffcc00; font-family: Abel, sans-serif; font-weight:bold; font-size: 36px}
            h4 {color: white; font-family: Abel, sans-serif; font-size: 22px}
            td {color: white; font-family: Abel, sans-serif}
            hr {border-color: #ffcc00}
            .tabborder {width: 25%%}
            .tabcontent {width: 50%%}
            .uicontent {border: 2px solid #ffcc00}
            .container {padding: 20px}

            @media only screen and (max-width: 640px) {
                .tabborder {width: 5%%}
                .tabcontent {width: 90%%}
                .container {padding: 5px}
                .uicontent {border: 0px}
            }
        </style>
    </head>
    <body>
        <div class='container'>
            <div class='uicontent'>
                <h2 align='center'>Weather Monitor<br>&nbsp;</h2>
                <div class='current-status-readout' align='center'>
                    <h4 class='temp-status'>Outside Temperature: <span></span>&deg;C&nbsp;</h4>
                    <h4 class='outlook-status'>Current Outlook: <span></span></h4>
                    <p class='location-status'>Device Location: <span></span></p>
                    <p class='error-message'><i><span></span></i></p>
                </div>
                <br>
                <div class='controls-area' align='center'>
                    <div class='update-button' style='color:dimGrey;font-family:Abel,sans-serif'>
                        <button type='submit' id='updater' style='height:32px;width:200px'>Update Monitor</button><br>&nbsp;
                    </div>
                    <div class='reboot-button' style='color:dimGrey;font-family:Abel,sans-serif'>
                        <button type='submit' id='rebooter' style='height:32px;width:200px'>Restart Monitor</button><br>&nbsp;
                    </div>
                </div>
                <div class='settings-area' align='center'>
                    <table width='100%%'>
                        <tr>
                            <td class='tabborder'>&nbsp;</td>
                            <td class='tabcontent'>
                                <div class='settings' style='background-color:#a30000;height:28px'>
                                    <p align='center'>Settings</p>
                                </div>
                                <div class='angle-radio'>
                                    <p>Display Angle</p>
                                    <input type='radio' name='angle' id='angle0' value='0' checked> 0&deg;<br>
                                    <input type='radio' name='angle' id='angle90' value='90'> 90&deg;<br>
                                    <input type='radio' name='angle' id='angle180' value='180'> 180&deg;<br>
                                    <input type='radio' name='angle' id='angle270' value='270'> 270&deg;
                                </div>
                                <hr>
                                <div class='slider'>
                                    <p class='brightness-status'>Brightness</p>
                                    <input type='range' name='brightness' id='brightness' value='15' min='1' max='15'>
                                    <table width='100%%'><tr><td width='50%%' align='left'><small>Low</small></td><td width='50%%' align='right'><small>High</small></td></tr></table>
                                    <p class='brightness-status' align='right'>Brightness: <span></span></p>
                                </div>
                                <div class='advancedsettings' style='background-color:#a30000'>
                                    <p class='showhide' align='center'>Show Advanced Settings</p>
                                    <div class='advanced' align='center'>
                                        <br>
                                        <div class='debug-checkbox' style='color:white;font-family:Abel,sans-serif'>
                                            <small><input type='checkbox' name='debug' id='debug' value='debug'> Debug Mode</small>
                                        </div>
                                        <br>
                                        <div class='reset-button' style='color:dimGrey;font-family:Abel,sans-serif'>
                                            <button type='submit' id='resetter' style='height:32px;width:200px'>Reset Monitor</button><br>&nbsp;
                                        </div>
                                    </div>
                                </div>
                            </td>
                            <td id='tabborder'>&nbsp;</td>
                        </tr>
                    </table>
                </div>
                <p class='colophon'>Weather Monitor &copy; Tony Smith, 2014-17<br>&nbsp;<br><a href='https://github.com/smittytone/Weather' target='_new'><img src='https://smittytone.github.io/images/rassilon.png' width='32' height='32'></a></p>
            </div>
        </div>

        <script src='https://ajax.googleapis.com/ajax/libs/jquery/3.2.1/jquery.min.js'></script>
        <script>
        $('.advanced').hide();

        // Variables
        var agenturl = '%s';
        var isMobile = false;

        // Set initial error message
        $('.error-message span').text('Forecast updates automatically every two minutes');

        // Get initial readings
        getState(updateReadout);

        // Set UI click actions
        $('.update-button button').click(update);
        $('.reboot-button button').click(reboot);
        $('.reset-button button').click(reset);
        $('#angle0').click(setangle);
        $('#angle90').click(setangle);
        $('#angle180').click(setangle);
        $('#angle270').click(setangle);
        $('#debug').click(setdebug);

        var slider = document.getElementById('brightness');
        $('.brightness-status span').text(slider.value);
        slider.addEventListener('mouseup', updateSlider);
        slider.addEventListener('touchend', updateSlider);

        $('.showhide').click(function(){
            $('.advanced').toggle();
            var isVis = $('.advanced').is(':visible');
            $('.showhide').text(isVis ? 'Hide Advanced Settings' : 'Show Advanced Settings');
        });

        // Functions
        function updateSlider() {
            $('.brightness-status span').text($('#brightness').val());
            setbright();
        }

        function updateReadout(data) {
            if (data.error) {
                $('.error-message span').text(data.error);
            } else {
                $('.temp-status span').text(data.temp);
                $('.outlook-status span').text(data.cast);
                $('.location-status span').text(data.location.place + ' (' + data.location.long + ', ' + data.location.lat + ')');
                $('.error-message span').text('Forecast updates automatically every two minutes');

                $('[name=angle]').each(function(i, v) {
                    if (data.angle == $(this).val()) {
                        $(this).prop('checked', true);
                    }
                });

                $('#brightness').val(data.bright);
                $('.brightness-status span').text(data.bright);
                document.getElementById('debug').checked = data.debug;
            }

            setTimeout(function() {
                getState(updateReadout);
            }, 120000);
        }

        function getState(callback) {
            // Request the current data
            $.ajax({
                url : agenturl + '/current',
                type: 'GET',
                success : function(response) {
                    response = JSON.parse(response);
                    if (callback) {
                        callback(response);
                    }
                }
            });
        }

        function update() {
            // Trigger a forecast update
            $.ajax({
                url : agenturl + '/update',
                type: 'POST',
                data: JSON.stringify({ 'action' : 'update' }),
                success : function(response) {
                    getState(updateReadout);
                }
            });
        }

        function reboot() {
            // Trigger a device restart
            $.ajax({
                url : agenturl + '/update',
                type: 'POST',
                data: JSON.stringify({ 'action' : 'reboot' }),
                success : function(response) {
                    getState(updateReadout);
                }
            });
        }

        function reset() {
            // Trigger a device reset
            $.ajax({
                url : agenturl + '/update',
                type: 'POST',
                data: JSON.stringify({ 'action' : 'reset' }),
                success : function(response) {
                    getState(updateReadout);
                }
            });
        }

        function setangle() {
            // Set the device screen angle
            var s;
            var r = document.getElementsByName('angle');
            for (var i = 0, length = r.length ; i < length ; i++) {
                if (r[i].checked) {
                    s = i;
                    break;
                }
            }

            // Set the correct angle based on the button checked
            if (s == 1) {
                s = 90;
            } else if (s == 2) {
                s = 180;
            } else if (s == 3) {
                s = 270;
            }

            $.ajax({
                url : agenturl + '/settings',
                type: 'POST',
                data: JSON.stringify({ 'angle' : s }),
            });
        }

        function setbright() {
            // Set the device screen brightness
            $.ajax({
                url : agenturl + '/settings',
                type: 'POST',
                data: JSON.stringify({ 'bright' : $('#brightness').val() })
            });
        }

        function setdebug() {
            // Tell the device to enter or leave debug mode
            $.ajax({
                url : agenturl + '/debug',
                type: 'POST',
                data: JSON.stringify({ 'debug' : document.getElementById('debug').checked })
            });
        }

        </script>
    </body>
</html>";

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
