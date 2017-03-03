// Weather
// Copyright 2016-17, Tony Smith

#require "DarkSky.class.nut:1.0.1"
#require "BuildAPIAgent.class.nut:1.1.1"
#require "Rocky.class.nut:2.0.0"

#import "../Location/location.class.nut"

// CONSTANTS

const refreshTime = 900;
const htmlString = @"
  <!DOCTYPE html>
  <html>
    <head>
      <title>Weather Monitor</title>
      <link rel='stylesheet' href='https://netdna.bootstrapcdn.com/bootstrap/3.1.1/css/bootstrap.min.css'>
      <meta name='viewport' content='width=device-width, height=device-height, initial-scale=1.0'>
      <style>
        .center { margin-left: auto; margin-right: auto; margin-bottom: auto; margin-top: auto; }
      </style>
    </head>
    <body>
      <div class='container' style='padding: 20px'>
      <div class='container' style='border: 2px solid gray'>
        <h2 class='text-center'>Weather Monitor<br>&nbsp;</h2>
        <div class='current-status'>
          <h4 class='temp-status' align='center'>Outside Temperature: <span></span>&deg;C&nbsp;</h4>
          <h4 class='outlook-status' align='center'>Outlook: <span></span></h4>
          <p class='error-message' align='center'><span></span></p>
        </div>
        <br>
        <div class='controls'>
          <form id='name-form' align='center'>
            <div class='update-button'>
              <button type='submit' id='updater' style='height:32px;width:200px'>Update Monitor</button><br>&nbsp;
            </div>
            <div class='reboot-button'>
              <button type='submit' id='rebooter' style='height:32px;width:200px'>Restart Monitor</button><br>&nbsp;
            </div>
          </form>
        </div> <!-- controls -->
        <p>&nbsp;<br>&nbsp;<small>Weather Monitor copyright &copy; Tony Smith, 2016-17</small><br>&nbsp;</p>
      </div>  <!-- container -->
      </div>
      <script src='https://ajax.googleapis.com/ajax/libs/jquery/3.1.0/jquery.min.js'></script>
      <script>
        var agenturl = '%s';
        getState(updateReadout);
        $('.update-button button').on('click', update);
        $('.reboot-button button').on('click', reboot);

        function triggerUpdate(e){
          e.preventDefault();
          update();
        }

        function updateReadout(data) {
          if (data.error) {
            $('.error-message span').text(data.error);
          } else {
            $('.temp-status span').text(data.temp);
            $('.outlook-status span').text(data.cast);
            $('.error-message span').text(' ');
          }

          setTimeout(function() {
            getState(updateReadout);
          }, 120000);
        }

        function getState(callback) {
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
          $.ajax({
            url : agenturl + '/update',
            type: 'POST',
            data: JSON.stringify({ 'action' : 'reboot' }),
            success : function(response) {
              getState(updateReadout);
            }
          });
        }

      </script>
    </body>
  </html>
";

// GLOCAL VARIABlES

local request = null;
local weather = null;
local locator = null;
local weatherTimer = null;
local restartTimer = null;
local build = null;
local settings = null;
local api = null;
local savedData = null;

local appName = "";
local appVersion = "3.2.";

local myLongitude = -0.123038;
local myLatitude = 51.568330;
local locationTime = -1;

local deviceSyncFlag = false;
local debug = false;

// FORECAST FUNCTIONS

function sendForecast(dummy) {
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

                if (debug) server.log("Summary: " + item.summary);

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

                local initial = sendData.cast.slice(0, 1);
                sendData.cast = initial.toupper() + sendData.cast.slice(1);

                // Send the icon name to the device
                sendData.icon <- item.icon;
                sendData.temp <- item.apparentTemperature;
                if (debug) server.log("Sending data to device");
                device.send("weather.show.forecast", sendData);

                // Log the outlook
                local celsius = sendData.temp.tofloat();
                local message = "Outlook: " + sendData.cast + ". Temperature: " + format("%.1f", celsius) + "C";
                if (debug) server.log(message);
                savedData = sendData;
            }
        }

        if (debug && "callCount" in data) server.log("Current Dark Sky API call tally: " + data.callCount + "/1000");
    }

    // Get the indoors temperature from the sensor agent
    // This only works if you have set up an Environment Tail Sensor,
    // see https://github.com/smittytone/EnvTailTempLog
    http.get(agent + "/state").sendasync(function(response) {
        if (response.statuscode == 200) {
            if (debug) server.log("Response from sensor agent: " + response.statuscode);
            if ("body" in response) {
                try {
                    local data = http.jsondecode(response.body);
                    device.send("weather.set.local.temp", data.temp);
                } catch (error) {
                    if (debug) server.error("Could not decode JSON from agent");
                }
            }
        } else {
            if (debug) server.error("Response from agent: " + response.statuscode + " " + response.body);
        }
    });

    // Tell the agent get the next forecast in 'refreshTime' seconds time
    if (weatherTimer) imp.cancelwakeup(weatherTimer);

    weatherTimer = imp.wakeup(refreshTime, function(){
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
        if (!("err" in locale)) {
            if (debug) server.log("Location: " + locale.longitude + ", " + locale.latitude);
            myLongitude = locale.longitude;
            myLatitude = locale.latitude;
            locationTime = time();
            sendForecast(true);
        } else {
            server.error(locale.err);
            imp.wakeup(10, function() {
                locationLookup(true);
            });
        }
    });

    deviceSyncFlag;
}

// SETTINGS FUNCTIONS

function getSettings(dummy) {
    device.send("weather.set.settings", settings);
    device.send("weather.set.build", appVersion);
}

// START PROGRAM

// If you are not using Squinter, uncomment the following lines
// and add your API keys:
// weather = DarkSky("YOUR_API_KEY");
// build = BuildAPIAccess("YOUR_BUILD_API_KEY");
// locator = Location("YOUR_API_KEY", debug);
// agent <- "YOUR ENV TAIL AGENT URL";

// If you are not using Squinter, omment out the following line:
#import "~/Dropbox/Programming/Imp/Codes/weather.nut"

// Populate name, version info
build.getModelName(imp.configparams.deviceid, function(err, data) {
    if (err) {
        server.error(err);
    } else {
        appName = data;
        build.getLatestBuildNumber(appName, function(err, data) {
            if (err) {
                server.error(err);
            } else {
                appVersion = appVersion + data;
            }
        }.bindenv(this));
    }
}.bindenv(this));

// Specify UK units for all forecasts, ie. temperatures in Celsius
weather.setUnits("uk");

// Set up settings record
local loadedSettings = server.load();

if (loadedSettings.len() == 0) {
    // No saved data, so save defaults
    settings = {};
    settings.angle <- 3;
    settings.bright <- 0;
    settings.debug <- false;
    debug = false;
    server.save(settings);
} else {
    settings = loadedSettings;
    if ("debug" in settings) {
        debug = settings.debug;
    } else {
        settings.debug <- debug;
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
    // Root request: just return standard HTML string
    context.send(200, format(htmlString, http.agenturl()));
});

// GET at /current returns the current forecast as JSON:
// { "cast" : "<the forecast>",
//   "icon" : "<the weather icon name>" }
// If there is an error, the JSON will contain the key 'error'
api.get("/current", function(context) {
    // Handle request for night dimmer status
    local data = {};
    if (savedData != null) {
        data = savedData;
    } else {
        data.error <- "Weather data not yet received. Please try again shortly";
    }

    data = http.jsonencode(data);
    context.send(200, data);
});

// POST at /update triggers an action, chosen by the JSON
// passed to the endpoint:
// { "action" : "<update/reboot>"  }
// 'update' causes the forecast to be updated
// 'reboot' causes the device to restart
api.post("/update", function(context) {
    // Apply setting for data from /dimmer endpoint
    try {
        local data = http.jsondecode(context.req.rawbody);

        if ("action" in data) {
            if (data.action == "update") {
                sendForecast(true);
            } else if (data.action == "reboot") {
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

// In five minutes' time, check if the device has not synced (as far as
// the agent knows) and is connected, ie. we have probably experienced
// an unexpected agent restart. If so, do a location lookup as if asked
// by a newly starting device
restartTimer = imp.wakeup(300, function() {
    if (!deviceSyncFlag) {
        if (device.isconnected()) {
            if (debug) server.log("Reacquiring location due to agent restart");
            locationLookup(true);
        }
    }
});
