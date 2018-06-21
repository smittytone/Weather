// Weather Monitor
// Copyright 2016-18, Tony Smith

// IMPORTS
#import "../Location/location.class.nut"
#import "../HT16K33Matrix/ht16k33matrix.class.nut"
#import "../generic/seriallog.nut"
#import "../generic/bootmessage.nut"
#import "../generic/disconnect.nut"


// CONSTANTS
const INITIAL_ANGLE = 270;
const INITIAL_BRIGHT = 10;
const RECONNECT_TIMEOUT = 15;
const RECONNECT_DELAY = 300;

// GLOBAL VARIABLES
local locator = null;
local matrix = null;
local savedForecast = null;
local savedData = null;
local savedIcon = null;
local localTemp = null;

local iconset = {};
local angle = INITIAL_ANGLE;
local bright = INITIAL_BRIGHT;
local debug = true;


// DEVICE FUNCTIONS
function intro() {
    // Fill in the matrix pixels from the outside in, in spiral fashion
    local x = 7, y = 0;
    local dx = 0, dy = 1;
    local mx = 6, my = 7;
    local nx = 0, ny = 0;


    for (local i = 0 ; i < 64 ; ++i) {
        matrix.plot(x, y, 1).draw();

        if (dx == 1 && x == mx) {
            dy = 1;
            dx = 0;
            mx = mx - 1;
        } else if (dx == -1 && x == nx) {
            nx = nx + 1;
            dy = -1;
            dx = 0;
        } else if (dy == 1 && y == my) {
            dy = 0;
            dx = -1;
            my = my - 1;
        } else if (dy == -1 && y == ny) {
            dx = 1;
            dy = 0;
            ny = ny + 1;
        }

        x = x + dx;
        y = y + dy;

        imp.sleep(0.015);
    }
}

function outro() {
    // Clear the matrix pixels from the inside out, in spiral fashion
    local x = 4, y = 3;
    local dx = -1, dy = 0;
    local mx = 5, my = 4;
    local nx = 3, ny = 2;

    for (local i = 0 ; i < 64 ; ++i) {
        matrix.plot(x, y, 0).draw();

        if (dx == 1 && x == mx) {
            dy = -1;
            dx = 0;
            mx = mx + 1;
        } else if (dx == -1 && x == nx) {
            nx = nx - 1;
            dy = 1;
            dx = 0;
        } else if (dy == 1 && y == my) {
            dy = 0;
            dx = 1;
            my = my + 1;
        } else if (dy == -1 && y == ny) {
            dx = -1;
            dy = 0;
            ny = ny - 1;
        }

        x = x + dx;
        y = y + dy;

        imp.sleep(0.015);
    }
}

function displayWeather(data) {
    // This function is called **solely** in response to a message from the server,
    // ie. it will not be called if the device is disconnected

    // Bail if we have duff data passed in
    if (data == null) {
        if (debug) seriallog.log("Agent sent null data");
        if (savedData) {
            data = savedData;
        } else {
            return;
        }
    }

    // Save the forecast
    savedData = data;

    // Clear this screen
    matrix.clearDisplay();

    // Display the weather by name, plus the temperature
    local s = "    " + data.cast.slice(0, 1).toupper() + data.cast.slice(1, data.cast.len()) + "  ";
    local ls = "Forecast: " + data.cast.slice(0, 1).toupper() + data.cast.slice(1, data.cast.len()) + ". Temperature: ";

    // Add the temperature
    local f = data.temp.tofloat();
    s = s + format("Out: %.1f", f) + "\x7F" + "c";
    ls = ls + format("Out: %.1f", f) + "\xC2\xB0" + "c";
    if (localTemp != null) {
        s = s + " In: " + localTemp + "\x7F" + "c";
        ls = ls + " In: " + localTemp + "\xC2\xB0" + "c";
    }

    // Draw text - spaces added to scroll everything off the matrix
    matrix.displayLine(s + "    ");
    savedForecast = s;

    if (debug) seriallog.log(ls);

    // Pause for half a second
    imp.sleep(0.5);

    // Display the weather icon
    local icon;

    try {
        icon = clone(iconset[data.icon]);
    } catch (error) {
        icon = clone(iconset[none]);
    }

    savedIcon = icon;
    matrix.displayIcon(savedIcon);
}

// START PROGRAM

// EARLY-START CODE
// Set up connectivity policy — this should come as early in the code as possible
disconnectionManager.eventCallback = function(event) {
    if ("message" in event) seriallog.log(event.message);

    if ("type" in event) {
        if (event.type == "connected") {
            // Re-acquire settings, Location
            agent.send("weather.get.settings", true);
            agent.send("weather.get.location", true);
        } else if (event.type == "disconnected") {
            // Notify of disconnection...
            matrix.displayLine("Disconnected");

            // ...and replay the last saved forecast
            if (savedForecast != null) {
                // 'savedForecast' will be null at first boot
                imp.sleep(1.0);
                matrix.displayLine(savedForecast + " ");
            }

            if (savedIcon != null) {
                // 'savedIcon' will be null at first boot
                imp.sleep(0.5);
                matrix.displayIcon(savedIcon);
            }
        } else if (event.type == "connecting") {
            // Notify of disconnection...
            seriallog.log("Attempting to connect...");
        }
    }
};
disconnectionManager.start();

// Set up impOS update notification
server.onshutdown(function(reason) {
    seriallog.log("server.onshutdown() called");
    if (reason == SHUTDOWN_NEWFIRMWARE && debug) seriallog.log("New impOS release available - restarting in 1 minute");
    if (reason == SHUTDOWN_NEWSQUIRREL && debug) seriallog.log("New Squirrel release available - restarting in 1 minute");
    if (reason == SHUTDOWN_NEWSQUIRREL || reason == SHUTDOWN_NEWFIRMWARE) {
        imp.wakeup(60, function() {
            server.restart();
        });
    }
});

// Set up hardware
hardware.i2c89.configure(CLOCK_SPEED_400_KHZ);
matrix = HT16K33Matrix(hardware.i2c89, 0x70, true);
matrix.init(bright, angle);
matrix.defineChar(0, [0x3C, 0x42, 0x95, 0xA1, 0xA1, 0x95, 0x42, 0x3C]);
matrix.defineChar(1, [0x70, 0x18, 0x7D, 0xB6, 0xBE, 0x3E]);
matrix.defineChar(2, [0xBE, 0xB6, 0x7D, 0x18, 0x70]);

// Splash screen animation
intro();
outro();

// Set up locator
locator = Location(null, true);

// Set up weather icons
iconset.clearday <- [0x89,0x42,0x18,0xBC,0x3D,0x18,0x42,0x91];
iconset.clearnight <- [0x0,0x0,0x0,0x81,0xE7,0x7E,0x3C,0x18];
iconset.rain <- [0x8C,0x5E,0x1E,0x5F,0x3F,0x9F,0x5E,0xC];
iconset.lightrain <- [0x8C,0x52,0x12,0x51,0x31,0x91,0x52,0xC];
iconset.snow <- [0x14,0x49,0x2A,0x1C,0x1C,0x2A,0x49,0x14];
iconset.sleet <- [0x4C,0xBE,0x5E,0xBF,0x5F,0xBF,0x5E,0xAC];
iconset.wind <- [0x14,0x14,0x14,0x14,0x14,0x55,0x55,0x22];
iconset.fog <- [0x55,0xAA,0x55,0xAA,0x55,0xAA,0x55,0xAA];
iconset.cloudy <- [0xC,0x1E,0x1E,0x1F,0x1F,0x1F,0x1E,0xC];
iconset.partlycloudy <- [0xC,0x12,0x12,0x11,0x11,0x11,0x12,0xC];
iconset.thunderstorm <- [0x0,0x0,0x0,0xF0,0x1C,0x7,0x0,0x0];
iconset.tornado <- [0x0,0x2,0x36,0x7D,0xDD,0x8D,0x6,0x2];
iconset.none <- [0x0,0x0,0x2,0xB9,0x9,0x6,0x0,0x0];

// Set up agent interaction
agent.on("weather.show.forecast", function(data) {
    // The agent has sent updated forecast data the for the device to display
    if (debug) seriallog.log("Forecast data received from agent");
    displayWeather(data);
});

agent.on("weather.set.local.temp", function(temp) {
    // The agent has sent update local temperature data for display
    if (debug) seriallog.log("Local temperature data received from agent");
    localTemp = temp;
});

agent.on("weather.set.debug", function(value) {
    // The user has told the device to enable or disable debugging messages
    debug = value;
});

agent.on("weather.set.angle", function(a) {
    // The user has updated the device brightness/display angle settings
    if (debug) seriallog.log("Updating display angle (" + a + ")");
    matrix.init(bright, a);
    angle = a;
    if (savedData != null) displayWeather(savedData);
});

agent.on("weather.set.bright", function(b) {
    // The user has updated the device brightness/display angle settings
    if (debug) seriallog.log("Updating display brightness (" + b + ")");
    matrix.init(b, angle);
    bright = b;
    if (savedData != null) displayWeather(savedData);
});

agent.on("weather.set.settings", function(data) {
    // The agent has relayed the device settings
    if (debug) seriallog.log("Received device settings from agent");
    local change = false;

    if ("bright" in data) {
        if (data.bright != bright) {
            bright = data.bright;
            change = true;
        }
    }

    if ("angle" in data) {
        if (data.angle != angle) {
            angle = data.angle;
            change = true;
        }
    }

    if ("debug" in data) {
        if (debug != data.debug) debug = data.debug;
    }

    if (change) {
        if (debug) seriallog.log("Updating display based on new settings");
        matrix.init(bright, angle);
        if (savedData != null) displayWeather(savedData);
    }
});

agent.on("weather.set.reboot", function(dummy) {
    // The user has asked the device to reboot
    local a = split(imp.getsoftwareversion(), "-");
    local v = a[2].tofloat();
    if (v > 38.0) {
      imp.reset();
    } else {
      server.restart();
    }
});

// At this point, the device will wait for a forecast from the agent.
// It will display this when it receives it, but we should check that the server is there
if (server.isconnected()) {
    // Tell the agent that the device is ready
    if (debug) seriallog.log("Requesting a forecast and settings from agent");
    agent.send("weather.get.settings", true);
    agent.send("weather.get.location", true);
} else {
    // Link down - try to connect to the server...
    disconnectionManager.connect();
}
