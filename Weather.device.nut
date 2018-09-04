// Weather Monitor
// Copyright 2016-18, Tony Smith

// IMPORTS
// NOTE If you are not using a tool like Squinter or impt, please
//      paste the contents of the file named in each line below into
//      the device code at this point, and then delete or comment out
//      all of the following #import statements
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
const DISPLAY_REFRESH_INTERVAL = 30;


// GLOBAL VARIABLES
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
local displayOn = true;
local displayRepeat = false;
local displayPeriod = 300;
local debug = true;
local connecting = false;


// DEVICE FUNCTIONS
function intro() {
    // This function sets the matrix pixels from the outside in, 
    // in a spiral pattern
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
    // This function clears the matrix pixels from the inside out, 
    // in a spiral pattern
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
    ds = ds + format("Out: %.1f", data.temp.tofloat()) + "\x7F" + "c";
    
    // ...and finally add the interior temperature, if we have it
    if (localTemp != null) ds = ds + " In: " + localTemp + "\x7F" + "c";
    
    // Prepare an icon to display
    local icon = null;

    try {
        icon = clone(iconset[data.icon]);
    } catch (error) {
        icon = clone(iconset[none]);
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
        matrix.displayIcon(icon);

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
        ls = ls + format("Out: %.1f", data.temp.tofloat()) + "\xC2\xB0" + "c";
        if (localTemp != null) ls = ls + " In: " + localTemp + "\xC2\xB0" + "c";
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

// Function to clear any display refresh timer in flight
function clearTimer() {
    if  (refreshTimer != null) {
        imp.cancelwakeup(refreshTimer);
        refreshTimer = null;
    }
}

// Disconnection Manager reporting handler function
function disHandler(event) {
    if ("message" in event) seriallog.log("Disconnection Manager says: " + event.message);

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
                matrix.displayIcon(savedIcon);
            }
        } else if (event.type == "connecting") {
            // Notify of disconnection...
            seriallog.log("Disconnection Manager says: Attempting to connect...");
            connecting = false;
        }
    }
}


// START PROGRAM

// Set up locator
locator = Location(null, true);

// Set up the disconnection handler function
disconnectionManager.eventCallback = disHandler;
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

// Set up hardware
hardware.i2c89.configure(CLOCK_SPEED_400_KHZ);
matrix = HT16K33Matrix(hardware.i2c89, 0x70);
matrix.init(bright, angle);

// Define non-standard characters: degree symbol, etc.
matrix.defineChar(0, [0x3C, 0x42, 0x95, 0xA1, 0xA1, 0x95, 0x42, 0x3C]);
matrix.defineChar(1, [0x70, 0x18, 0x7D, 0xB6, 0xBE, 0x3E]);
matrix.defineChar(2, [0xBE, 0xB6, 0x7D, 0x18, 0x70]);

// Splash screen animation
intro();
outro();

// Set up weather icons
iconset.clearday <- [0x89,0x42,0x18,0xBC,0x3D,0x18,0x42,0x91];
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
iconset.clearnight <- [0x3C,0x42,0x81,0xC3,0xFF,0xFF,0x7E,0x3C];
// iconset.clearnight <- [0x0,0x0,0x0,0x81,0xE7,0x7E,0x3C,0x18];

// Set up agent interaction
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
    debug = value;
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
    if (debug) seriallog.log("Turning repeat mode " + (r ? "on" : "off"));
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
    local v = bootinfo.version().tofload();
    if (v > 38.0) {
      imp.reset();
    } else {
      server.restart();
    }
});

agent.on("weather.set.settings", function(data) {
    // The agent has relayed the device settings
    if (debug) seriallog.log("Received device settings from agent");
    
    displayOn = data.power;
    bright = data.bright;
    angle = data.angle;
    debug = data.debug;
    displayRepeat = data.repeat;
    displayPeriod = data.period * 60;

    if (displayOn) {
        matrix.init(bright, angle);
    } else {
        matrix.clearDisplay();
    }

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
