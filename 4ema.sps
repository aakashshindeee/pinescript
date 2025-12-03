//@version=6
strategy("4 EMA Crossover — Trend Rider (V6)",
     overlay=true,
     initial_capital=100000,
     default_qty_type=strategy.percent_of_equity,
     default_qty_value=100,
     commission_type=strategy.commission.percent,
     commission_value=0.0,
     pyramiding=0)

// --- 1. EMA & Risk Inputs ---
len1 = input.int(8, minval=1, title="MA1")
len2 = input.int(13, minval=1, title="MA2")
len3 = input.int(21, minval=1, title="MA3")
len4 = input.int(55, minval=1, title="MA4")

// HTF Confirmation Inputs
htf_timeframe = input.timeframe("60", title="Higher Timeframe (HTF) for Trend")
htf_slow_len = input.int(200, minval=1, title="HTF EMA 200 Length")

// Standard Filters
rsiPeriod = input.int(14, minval=1, title="RSI Period")
atrPeriod = input.int(14, minval=1, title="ATR Period")
atrSidewaysMultiplier = input.float(1.5, minval=0.1, step=0.1, title="ATR Sideways Filter Multiplier") 

// --- PROFIT OPTIMIZATION INPUTS ---
// NEW: Exit Mode Selection
exit_mode = input.string("ATR Trailing", options=["ATR Trailing", "Ride EMA Wave"], title="Exit Strategy Mode")

// Mode A: ATR Settings
atrStopMultiplier = input.float(3.5, minval=0.1, step=0.1, title="ATR Trail Distance (For ATR Mode)") 

// Mode B: EMA Ride Settings
ride_ema_length = input.int(21, title="EMA to Ride (Exit on Close Below)")

// RSI Settings
use_rsi_exit = input.bool(false, title="Exit on RSI Exhaustion? (Disable for big trends)")
rsi_exit_level = input.int(80, title="RSI Exhaustion Level (80/-20)")


// --- 2. Indicators & HTF Confirmation ---
ma1 = ta.ema(close, len1)
ma2 = ta.ema(close, len2)
ma3 = ta.ema(close, len3)
ma4 = ta.ema(close, len4) // 55 EMA

// EMA for "Ride" Exit
maRide = ta.ema(close, ride_ema_length)

// HTF EMAs
htf_ma55 = request.security(syminfo.tickerid, htf_timeframe, ta.ema(close, 55))
htf_ma200 = request.security(syminfo.tickerid, htf_timeframe, ta.ema(close, htf_slow_len))

htf_long_trend = htf_ma55 > htf_ma200
htf_short_trend = htf_ma55 < htf_ma200

// Momentum & Volatility
rsiValue = ta.rsi(close, rsiPeriod)
atrValue = ta.atr(atrPeriod)
isSideways = (ta.highest(high, 10) - ta.lowest(low, 10)) < (atrValue * atrSidewaysMultiplier)
longMomentumCond = rsiValue > 50
shortMomentumCond = rsiValue < 50


// --- 3. Crossover & Filtered Signals ---
longCond = ma1 > ma4 and ma2 > ma4 and ma3 > ma4 and longMomentumCond and not isSideways and htf_long_trend
shortCond = ma1 < ma4 and ma2 < ma4 and ma3 < ma4 and shortMomentumCond and not isSideways and htf_short_trend

var int CondIni = 0
CondIni := longCond ? 1 : shortCond ? -1 : CondIni[1]

longSignal = longCond and CondIni[1] == -1
shortSignal = shortCond and CondIni[1] == 1


// --- 4. Strategy Orders ---
if longSignal
    strategy.entry("Long", strategy.long)
else if shortSignal
    strategy.entry("Short", strategy.short)


// --- 5. EXIT LOGIC CALCULATION ---

// ATR Logic (Calculated regardless of mode for initial stop protection)
var float tradeAtr = na
if longSignal or shortSignal
    tradeAtr := atrValue

slDistance = tradeAtr * atrStopMultiplier

var float longTrailPrice = na
var float shortTrailPrice = na

// Update Trailing Stop for LONG (ATR Mode)
if strategy.position_size > 0
    float potentialStop = high - slDistance
    if na(longTrailPrice) 
        longTrailPrice := potentialStop
    else
        longTrailPrice := math.max(longTrailPrice, potentialStop)
else
    longTrailPrice := na

// Update Trailing Stop for SHORT (ATR Mode)
if strategy.position_size < 0
    float potentialStop = low + slDistance
    if na(shortTrailPrice)
        shortTrailPrice := potentialStop
    else
        shortTrailPrice := math.min(shortTrailPrice, potentialStop)
else
    shortTrailPrice := na


// --- 6. EXECUTE EXITS ---



[Image of candlestick chart with moving average support]


// MODE 1: ATR TRAILING (Wide)
if exit_mode == "ATR Trailing"
    if strategy.position_size > 0
        strategy.exit("Trail Long", "Long", stop=longTrailPrice, comment="ATR Trail")
    if strategy.position_size < 0
        strategy.exit("Trail Short", "Short", stop=shortTrailPrice, comment="ATR Trail")

// MODE 2: RIDE EMA WAVE (Pure Trend Following)
// This ignores price targets and only exits if price CLOSES past the specific EMA
if exit_mode == "Ride EMA Wave"
    // Hard Stop Loss (Emergency Protection based on entry ATR) to prevent total ruin
    // We use the initial ATR stop just for safety, but rely on EMA for profit taking
    emergencyLongStop = strategy.opentrades.entry_price(strategy.opentrades - 1) - slDistance
    emergencyShortStop = strategy.opentrades.entry_price(strategy.opentrades - 1) + slDistance

    if strategy.position_size > 0
        if ta.crossunder(close, maRide) // Price closed below the EMA
            strategy.close("Long", comment="Trend Break (EMA)")
        else
            strategy.exit("Protect Long", "Long", stop=emergencyLongStop) // Just in case of crash

    if strategy.position_size < 0
        if ta.crossover(close, maRide) // Price closed above the EMA
            strategy.close("Short", comment="Trend Break (EMA)")
        else
            strategy.exit("Protect Short", "Short", stop=emergencyShortStop)

// OPTIONAL RSI EXHAUSTION
if use_rsi_exit
    if strategy.position_size > 0 and rsiValue > rsi_exit_level
        strategy.close("Long", comment="RSI Overbought")
    if strategy.position_size < 0 and rsiValue < (100 - rsi_exit_level)
        strategy.close("Short", comment="RSI Oversold")


// --- 7. Plots ---
plot(ma1, title="MA1", color=color.blue, display=display.none)
plot(ma4, title="MA4 (55)", color=color.orange, linewidth=2)
plot(exit_mode == "Ride EMA Wave" ? maRide : na, title="Ride EMA", color=color.white, linewidth=2)

// Plot the Trailing Stop Line only if in ATR Mode
plot(exit_mode == "ATR Trailing" and strategy.position_size > 0 ? longTrailPrice : na, title="Long Trail", color=color.red, style=plot.style_linebr)
plot(exit_mode == "ATR Trailing" and strategy.position_size < 0 ? shortTrailPrice : na, title="Short Trail", color=color.red, style=plot.style_linebr)

plotshape(longSignal, title="Buy", text="B", style=shape.labelup, location=location.belowbar, color=color.green, textcolor=color.white)
plotshape(shortSignal, title="Sell", text="S", style=shape.labeldown, location=location.abovebar, color=color.red, textcolor=color.white)