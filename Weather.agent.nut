// Weather Monitor
// Copyright 2016-17, Tony Smith

#require "DarkSky.class.nut:1.0.1"
#require "BuildAPIAgent.class.nut:1.1.1"
#require "Rocky.class.nut:2.0.0"

#import "../Location/location.class.nut"

// CONSTANTS

const refreshTime = 900;
const htmlString = @"<!DOCTYPE html><html lang='en-US'><meta charset='UTF-8'>
<html>
  <head>
    <title>Weather Monitor</title>
    <link rel='stylesheet' href='https://netdna.bootstrapcdn.com/bootstrap/3.1.1/css/bootstrap.min.css'>
    <link href='//fonts.googleapis.com/css?family=Abel' rel='stylesheet'>
    <link href='//fonts.googleapis.com/css?family=Oswald' rel='stylesheet'><meta name='viewport' content='width=device-width, height=device-height, initial-scale=1.0'>
    <style>
      .center { margin-left: auto; margin-right: auto; margin-bottom: auto; margin-top: auto; }
      body {background-color: #b30000;}
      p {color: white; font-family: Abel}
      h2 {color: #ffcc00; font-family: Abel; font-weight:bold}
      h4 {color: white; font-family: Abel}
      td {color: white; font-family: Abel}
      hr {border-color: #ffcc00}
      .error-message {color:#ffcc00}
    </style>
  </head>
  <body>
    <div class='container' style='padding: 20px'>
      <div class='container' style='border: 2px solid #ff9900'>
        <h2 class='text-center'>Weather Monitor <span></span><br>&nbsp;</h2>
        <div class='current-status'>
          <h4 class='temp-status' align='center'>Outside Temperature: <span></span>&deg;C&nbsp;</h4>
          <h4 class='outlook-status' align='center'>Current Outlook: <span></span></h4>
          <p class='location-status' align='center'>Device Location: <span></span></p>
          <p align='center'>Forecast updates automatically every two minutes</p>
          <p class='error-message' align='center'><i><span></span></i></p>
        </div>
        <br>
        <div class='controls' align='center'>
          <form id='button-form'>
            <div class='update-button' style='color:dimGrey;font-family:Abel'>
              <button type='submit' id='updater' style='height:32px;width:200px'>Update Monitor</button><br>&nbsp;
            </div>
            <div class='reboot-button' style='color:dimGrey;font-family:Abel'>
              <button type='submit' id='rebooter' style='height:32px;width:200px'>Restart Monitor</button><br>&nbsp;
            </div>
          </form>
          <hr>
        </div>
        <div class='controls'>
          <table width='100%%'>
            <tr>
              <td width='25%%'>&nbsp;</td>
              <td width='50%%'>
              <form id='settings'>
                <div class='angle-radio'>
                  <p><b>Display Angle</b></p>
                  <input type='radio' name='angle' value='0' checked> 0&deg;<br>
                  <input type='radio' name='angle' value='90'> 90&deg;<br>
                  <input type='radio' name='angle' value='180'> 180&deg;<br>
                  <input type='radio' name='angle' value='270'> 270&deg;
                </div>
                <div class='slider'>
                  <p class='brightness-status'>&nbsp;<br><b>Brightness</b> <span></span></p>
                  <input type='range' name='brightness' id='brightness' value='15' min='0' max='15'>
                </div>
                <hr>
                <div class='debug-checkbox' style='color:white;font-family:Abel'>
                  <small><input type='checkbox' name='debug' id='debug' value='debug'> Debug Mode</small>
                </div>
              </form>
              </td>
              <td width='25%%'>&nbsp;</td>
            </tr>
          </table>
        </div>
        <p class='text-center' style='font-family:Oswald'>&nbsp;<br>&nbsp;<small>Weather Monitor copyright &copy; Tony Smith, 2014-17</small><br>&nbsp;<br><img src='https://dl.dropboxusercontent.com/u/3470182/rassilon.png' width='32' height='32'></p>
      </div>
    </div>

    <script src='https://ajax.googleapis.com/ajax/libs/jquery/3.1.0/jquery.min.js'></script>
    <script>
      var agenturl = '%s';
      // Get initial readings
      getState(updateReadout);

      // Set UI click actions
      $('.update-button button').on('click', update);
      $('.reboot-button button').on('click', reboot);
      $('input:radio[name=angle]').click(setangle);
      $('input:checkbox[name=debug]').click(setdebug);

      var slider = document.getElementById('brightness');
      $('.brightness-status span').text(slider.value);

      slider.addEventListener('mouseup', function() {
        $('.brightness-status span').text(slider.value);
        setbright();
      });

      slider.addEventListener('touchend', function() {
        $('.brightness-status span').text(slider.value);
        setbright();
      });

      function updateReadout(data) {
        if (data.error) {
          $('.error-message span').text(data.error);
        } else {
          $('.temp-status span').text(data.temp);
          $('.outlook-status span').text(data.cast);
          $('.location-status span').text(data.location.long + ', ' + data.location.lat);
          $('.error-message span').text(' ');
          $('.text-center span').text(data.vers);

          $('[name=angle]').each(function(i, v) {
            if (data.angle == $(this).val()) {
              $(this).prop('checked', true);
            }
          });

           $('[name=brightness]').val(data.bright);
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
          data: JSON.stringify({ 'bright' : $('[name=brightness]').val() })
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

    deviceSyncFlag = true;
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
context.send(200, format(htmlString, http.agenturl()));
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
    data.location <- loc;
    data.angle <- settings.angle.tostring();
    data.bright <- settings.bright;
    data.debug <- settings.debug;
    data.vers <- appVersion.slice(0, 3);
    data = http.jsonencode(data);
    context.send(200, data);
});

// POST at /update triggers an action, chosen by the JSON
// passed to the endpoint:
// { "action" : "<update/reboot>"  }
// 'update' causes the forecast to be updated
// 'reboot' causes the device to restart
api.post("/update", function(context) {
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
