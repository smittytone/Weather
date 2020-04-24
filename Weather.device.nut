// Weather Monitor
// Copyright 2016-20, Tony Smith

// ********** IMPORTS **********
// If you are NOT using Squinter or a similar tool, replace the following #import statement(s)
// with the contents of the named file(s):
#import "../HT16K33Matrix-Squirrel/ht16k33matrix.class.nut"     // Source file in https://github.com/smittytone/HT16K33Matrix
#import "../Location/location.class.nut"                        // Source file in https://github.com/smittytone/Location
#import "../generic-squirrel/seriallog.nut"                     // Source file in https://github.com/smittytone/generic
#import "../generic-squirrel/disconnect.nut"                    // Source file in https://github.com/smittytone/generic
#import "../generic-squirrel/crashReporter.nut"                 // Source code: https://github.com/smittytone/generic


// ********** CONSTANTS **********
const INITIAL_ANGLE = 270;
const INITIAL_BRIGHT = 5;
const RECONNECT_TIMEOUT = 15;
const RECONNECT_DELAY = 300;
const DISPLAY_REFRESH_INTERVAL = 30;


// ********** GLOBAL VARIABLES **********
local locator = null;
local matrix = null;
local savedForecast = null;
local savedData = null;
local savedIcon = null;
local localTemp = null;
local refreshTimer = null;
local iconset = {};
local angle = INITIAL_ANGLE;
local bright = INITIAL_BRIGHT;
local displayPeriod = 300;
local displayOn = true;
local displayRepeat = false;
local debug = false;
local connecting = false;
local inverse = false;


// ********** DISPLAY FUNCTIONS **********

function intro() {
    // This function sets the matrix pixels from the outside in, in a spiral pattern
    local x = 7, y = 0;
    local dx = 0, dy = 1;
    local mx = 6, my = 7;
    local nx = 0, ny = 0;

    for (local i = 0 ; i < 64 ; i++) {
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
    // This function clears the matrix pixels from the inside out, in a spiral pattern
    local x = 4, y = 3;
    local dx = -1, dy = 0;
    local mx = 5, my = 4;
    local nx = 3, ny = 2;

    for (local i = 0 ; i < 64 ; i++) {
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
    // This function is called in response to a message from the server containing
    // a new hour-ahead weather forecast, or in response to a timer-fire if the user
    // has applied the 'refresh display' setting. Refreshing the display shows the
    // current forecast again, and the current forecast will continue to be shown
    // if the device goes offline for any period

    // Bail if we have no data passed in
    if (data == null) {
        if (debug) seriallog.log("Agent sent null data");
        if (savedData != null) {
            // Use a saved forecast, if we have one
            data = savedData;
        } else {
            return;
        }
    }

    // Prepare the string used to display the weather forecastt by name...
    local ds = "    " + data.cast.slice(0, 1).toupper() + data.cast.slice(1, data.cast.len()) + "  ";

    // ...then add the forecast temperature...
    ds +=  (format("Out: %.1f", data.temp) + "\x7F" + "c");

    // ...and finally add the interior temperature, if we have it
    if (localTemp != null) ds += (format(" In: %.1f", localTemp) + "\x7F" + "c");

    // Prepare an icon to display
    local icon = null;

    // Use a 'try... catch' in case the table 'iconset' has no key
    // that matches the string 'data.icon' (choose 'none' if that's the case)
    try {
        icon = iconset[data.icon];
    } catch (error) {
        icon = iconset.none;
    }

    // Store the current icon and forecast string
    // (we will need to re-use it if the 'refresh display' timer fires, or
    //  the device goes offline and receives no new forecasts)
    savedIcon = icon;
    savedForecast = ds;
    savedData = data;

    // Display the forecast if we should display it
    if (displayOn) {
        // Clear this screen
        matrix.clearDisplay();

        // Draw text - spaces added to scroll everything off the matrix
        matrix.displayLine(ds + "    ");

        // Pause for half a second
        imp.sleep(0.5);

        // Display the weather icon
        matrix.displayCharacter(icon);

        // Set up a timer for the display repeat, if refresh display mode is enabled
        if (savedData != null && displayRepeat) {
            refreshTimer = imp.wakeup(displayPeriod, function() {
                refreshTimer = null;
                displayWeather(savedData);
            });
        }
    }

    // Present debug info if we should
    if (debug) {
        local ls = "Forecast: " + data.cast.slice(0, 1).toupper() + data.cast.slice(1, data.cast.len()) + ". Temperature: ";
        ls += (format("Out: %.1f", data.temp.tofloat()) + "\xC2\xB0" + "c");
        if (localTemp != null) ls += (format(" In: %.1f", localTemp) + "\xC2\xB0" + "c");
        seriallog.log(ls);
        seriallog.log("Current repeat settings: period is " + displayPeriod + "s, repeat is " + (displayRepeat ? "on" : "off"));
    }
}

// Function to insert new data into the display cycle
function refreshDisplay(data) {
    // Call this function when you need to update the display manually
    // It will halt the periodic refresh timer (set in 'displayWeather()')
    clearTimer();
    displayWeather(data);
}


// ********** UTILITY FUNCTIONS **********
function clearTimer() {
    // Function to clear any display refresh timer in flight
    if  (refreshTimer != null) {
        imp.cancelwakeup(refreshTimer);
        refreshTimer = null;
    }
}

// ********** CONNECTION/RECONNECTION FUNCTIONS **********
function discHandler(event) {
    // This is the Disconnection Manager report handler
    if ("message" in event && debug) seriallog.log("Disconnection Manager says: " + event.message);

    if ("type" in event) {
        if (event.type == "connected") {
            // Re-acquire settings, location after a disconnection
            if (connecting) {
                connecting = false;
                agent.send("weather.get.settings", true);
            }
        } else if (event.type == "disconnected") {
            // Notify of disconnection...
            if (displayOn) matrix.displayLine("Disconnected");

            // ...and replay the last saved forecast
            if (savedForecast != null && displayOn) {
                // 'savedForecast' will be null at first boot
                imp.sleep(1.0);
                matrix.displayLine(savedForecast + " ");
            }

            if (savedIcon != null && displayOn) {
                // 'savedIcon' will be null at first boot
                imp.sleep(0.5);
                matrix.displayCharacter(savedIcon);
            }
        } else if (event.type == "connecting") {
            // Notify of disconnection...
            seriallog.log("Disconnection Manager says: Attempting to connect...");
            connecting = false;
        }
    }
}


// ********** RUNTIME START **********

// Load in generic boot message code
// If you are NOT using Squinter or a similar tool, replace the following #import statement(s)
// with the contents of the named file(s):
#import "../generic-squirrel/bootmessage.nut"        // Source code: https://github.com/smittytone/generic

// Set up the crash reporter
crashReporter.init();

// Set up the geographical locator. The agent will use this when
// the device code sends a "weather.get.settings" message to it
locator = Location();

// Set up the disconnection handler function and begin monitoring
disconnectionManager.eventCallback = discHandler;
disconnectionManager.reconnectDelay = RECONNECT_DELAY;
disconnectionManager.reconnectTimeout = RECONNECT_TIMEOUT;
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

// Set up the I2C LED matrix display hardware
hardware.i2c89.configure(CLOCK_SPEED_400_KHZ);
matrix = HT16K33Matrix(hardware.i2c89, 0x70);
matrix.init(INITIAL_BRIGHT, INITIAL_ANGLE);

// Splash screen animation part one
intro();

// Set up weather icons using user-definable characters
matrix.defineCharacter(0, "\x91\x42\x18\x3d\xbc\x18\x42\x89"); //"\x89\x42\x18\xBC\x3D\x18\x42\x91"
matrix.defineCharacter(1, "\x31\x7A\x78\xFA\xFC\xF9\x7A\x30"); //"\x8C\x5E\x1E\x5F\x3F\x9F\x5E\x0C"
matrix.defineCharacter(2, "\x31\x7A\x78\xFA\xFC\xF9\x7A\x30");
matrix.defineCharacter(3, "\x28\x92\x54\x38\x38\x54\x92\x28"); // \x14\x49\x2A\x1C\x1C\x2A\x49\x14
matrix.defineCharacter(4, "\x32\x7D\x7A\xFD\xFA\xFD\x7A\x35"); // \x4C\xBE\x5E\xBF\x5F\xBF\x5E\xAC
matrix.defineCharacter(5, "\x28\x28\x28\x28\x28\xAA\xAA\x44"); // \x14\x14\x14\x14\x14\x55\x55\x22
matrix.defineCharacter(6, "\xAA\x55\xAA\x55\xAA\x55\xAA\x55"); // \x55\xAA\x55\xAA\x55\xAA\x55\xAA
matrix.defineCharacter(7, "\x30\x78\x78\xF8\xF8\xF8\x78\x30"); // \x0C\x1E\x1E\x1F\x1F\x1F\x1E\x0C
matrix.defineCharacter(8, "\x30\x48\x48\x88\x88\x88\x48\x30"); // \x0C\x12\x12\x11\x11\x11\x12\x0C
matrix.defineCharacter(9, "\x00\x00\x00\x0F\x38\xE0\x00\x00"); // \x00\x00\x00\xF0\x1C\x07\x00\x00
matrix.defineCharacter(10, "\x00\x40\x6C\xBE\xBB\xB1\x60\x40"); // \x00\x02\x36\x7D\xDD\x8D\x06\x02
matrix.defineCharacter(11, "\x3C\x42\x81\xC3\xFF\xFF\x7E\x3C"); // \x3C\x42\x81\xC3\xFF\xFF\x7E\x3C
matrix.defineCharacter(12, "\x00\x00\x40\x9D\x90\x60\x00\x00"); // \x00\x00\x02\xB9\x09\x06\x00\x00

// Set up a table to map incoming weather condition names
// (eg. "clearday") to user-definable character Ascii values
iconset.clearday <-     0;
iconset.rain <-         1;
iconset.lightrain <-    2;
iconset.snow <-         3;
iconset.sleet <-        4;
iconset.wind <-         5;
iconset.fog <-          6;
iconset.cloudy <-       7;
iconset.partlycloudy <- 8;
iconset.thunderstorm <- 9;
iconset.tornado <-      10;
iconset.clearnight <-   11;
iconset.none <-         12;

// Set up agent interaction handlers
agent.on("weather.show.forecast", function(data) {
    // The agent has sent updated forecast data the for the device to display
    if (debug) seriallog.log("Forecast data received from agent");
    refreshDisplay(data);
});

agent.on("weather.set.local.temp", function(temp) {
    // The agent has sent update local temperature data for display
    if (debug) seriallog.log("Local temperature data received from agent");
    localTemp = temp;
});

agent.on("weather.set.debug", function(value) {
    // The user has told the device to enable or disable debugging messages
    seriallog.log("Debugging turned " + (value ? "on" : "off"));
    debug = value;
    matrix.setDebug(debug, false);
    locator.setDebug(debug);
});

agent.on("weather.set.angle", function(a) {
    // The user has updated the device brightness/display angle settings
    if (debug) seriallog.log("Updating display angle (" + a + ")");
    angle = a;
    if (displayOn) {
        matrix.init(bright, a);
        if (savedData != null) refreshDisplay(savedData);
    }
});

agent.on("weather.set.bright", function(b) {
    // The user has updated the device brightness/display angle settings
    if (debug) seriallog.log("Updating display brightness (" + b + ")");
    bright = b;
    if (displayOn) {
        matrix.init(b, angle);
        if (savedData != null) refreshDisplay(savedData);
    }
});

agent.on("weather.set.power", function(p) {
    // The user has updated the device display state
    if (debug) seriallog.log("Turning screen " + (p ? "on" : "off"));
    if (displayOn && !p) matrix.clearDisplay();
    displayOn = p;
    if (displayOn && savedData != null) refreshDisplay(savedData);
});

agent.on("weather.set.repeat", function(shouldRepeat) {
    // The user has enabled or disabled repeat mode
    // ie. the display repeats periodically or is only updated when a new forecast comes in
    if (debug) seriallog.log("Turning repeat mode " + (shouldRepeat ? "on" : "off"));
    displayRepeat = shouldRepeat;
    if (shouldRepeat && displayOn && savedData != null) refreshDisplay(savedData);
    if (!shouldRepeat) clearTimer();
});

agent.on("weather.set.period", function(period) {
    // Convert minutes (agent setting) to seconds (device setting)
    displayPeriod = period * 60;

    // If we're repeating the display, refresh it now
    if (displayRepeat) {
        clearTimer();
        if (savedData != null) refreshDisplay(savedData);
    }
});

agent.on("weather.set.reboot", function(dummy) {
    // The user has asked the device to reboot
    local v = bootinfo.version().tofloat();
    if (v > 38.0) {
        imp.reset();
    } else {
        server.restart();
    }
});

agent.on("weather.set.video", function(state) {
    if (inverse != state) {
        matrix.setInverseVideo(state);
        inverse = state;
    }
});

agent.on("weather.set.settings", function(data) {
    // The agent has relayed the device settings
    displayOn = data.power;
    bright = data.bright;
    angle = data.angle;
    debug = data.debug;
    displayRepeat = data.repeat;
    displayPeriod = data.period * 60;
    inverse = data.inverse;

    if (displayOn) {
        matrix.init(bright, angle);
        matrix.setInverseVideo(inverse);
    } else {
        matrix.clearDisplay();
    }

    // Set class debugging level
    matrix.setDebug(debug, false);
    locator.setDebug(debug);

    if (debug) seriallog.log("Received device settings from agent");

    // The device's settings are now in place, so get its location
    agent.send("weather.get.location", true);
});


// If the device is connected, request its settings from the agent.
// This will in turn get the device's location, causing the agent to
// begin sending forecasts every 15 minutes.
if (server.isconnected()) {
    // Tell the agent that the device is ready
    if (debug) seriallog.log("Requesting a forecast and settings from agent");
    agent.send("weather.get.settings", true);
} else {
    // Link down - try to connect to the server...
    disconnectionManager.connect();
}

// Splash screen animation part two
outro();