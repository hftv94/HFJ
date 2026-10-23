#!/usr/bin/env bash
# يولّد HFJ_Pro_Strategy.pine من المؤشر: نفس الإشارات والفلتر، مع تنفيذ صفقات Risk:Reward (1:2 افتراضياً)
set -euo pipefail
cd "$(dirname "$0")"
src=HFJ_Pro_Suite.pine
out=HFJ_Pro_Strategy.pine

sed -e 's|^// HFJ Pro Suite v\([0-9.]*\) — .*|// HFJ Pro Strategy v\1 — نسخة استراتيجية من HFJ Pro Suite: دخول بالإشارات المقبولة فقط، وقف خلف القاع/القمة وهدف 1:2|' \
    -e 's|^indicator("HFJ Pro Suite", shorttitle = "HFJ Pro", overlay = true, \(.*\))$|strategy("HFJ Pro Strategy", shorttitle = "HFJ Strat", overlay = true, \1, initial_capital = 10000, currency = currency.USD, process_orders_on_close = true, pyramiding = 0, commission_type = strategy.commission.percent, commission_value = 0.02, slippage = 1)|' \
    -e 's|^string s_tpMode = input.string("ATR 50", "TP mode"|string s_tpMode = input.string("Risk:Reward", "TP mode"|' \
    -e '/^alertcondition(/d' \
    "$src" > "$out"

grep -q '^strategy("HFJ Pro Strategy"' "$out" || { echo "indicator() line not found" >&2; exit 1; }
grep -q 'input.string("Risk:Reward", "TP mode"' "$out" || { echo "TP mode input not found" >&2; exit 1; }

cat >> "$out" <<'PINE'

// ════════════════════════════════════════════════════════════
// 16. الاستراتيجية: دخول عند الإشارة المقبولة، وقف tSL، هدف TP2 (= R:R target × الوقف)
// ════════════════════════════════════════════════════════════
const string G_STR = "STRATEGY"
float st_risk = input.float(1.0, "% Risk per trade", minval = 0.1, maxval = 10, step = 0.1, group = G_STR, tooltip = "حجم الصفقة يُحسب بحيث يكون الوقف = هذه النسبة من رصيد الحساب")
bool  st_be   = input.bool(false, "Break-even at TP1 (1R)", group = G_STR, tooltip = "نقل الوقف إلى سعر الدخول عند الوصول إلى 1R")
bool  st_flip = input.bool(true, "Exit on trend flip", group = G_STR, tooltip = "إغلاق الصفقة إذا انقلب الاتجاه ضدها قبل الوقف أو الهدف")
int   st_from = input.time(timestamp("01 Jan 2024 00:00 +0000"), "Start date", group = G_STR)

bool  st_min1 = input.bool(true, "Min 1 contract (futures)", group = G_STR, tooltip = "العقود الآجلة: إذا كانت المخاطرة أقل من عقد واحد يُدخل بعقد واحد. استخدم العقود الصغيرة (MES / MNQ / MGC / MCL) أو ارفع رأس المال من Properties")

// حجم الصفقة: المخاطرة بعملة الحساب ÷ (مسافة الوقف × قيمة النقطة × سعر تحويل عملة الرمز)
float stRate = nz(request.currency_rate(syminfo.currency, "USD", ignore_invalid_currency = true), 1.0)
bool  stOk   = time >= st_from
float stDist = math.abs(tEntry - tSL)
float stRaw  = stDist > 0 ? strategy.equity * st_risk / 100 / (stDist * syminfo.pointvalue * stRate) : 0.0
float stQty  = syminfo.type == "futures" ? (st_min1 ? math.max(math.floor(stRaw), 1) : math.floor(stRaw)) : syminfo.type == "forex" ? math.floor(stRaw / 1000) * 1000 : syminfo.type == "stock" or syminfo.type == "fund" ? math.floor(stRaw) : stRaw

if buySig and stOk and stQty > 0
    strategy.entry("Long", strategy.long, qty = stQty)
    strategy.exit("Long X", "Long", stop = tSL, limit = f_tpPrice(2))
if sellSig and stOk and stQty > 0
    strategy.entry("Short", strategy.short, qty = stQty)
    strategy.exit("Short X", "Short", stop = tSL, limit = f_tpPrice(2))

if st_be and tpHitNow and tpHit == 1
    if strategy.position_size > 0
        strategy.exit("Long X", "Long", stop = tEntry, limit = f_tpPrice(2))
    if strategy.position_size < 0
        strategy.exit("Short X", "Short", stop = tEntry, limit = f_tpPrice(2))

if st_flip and flipExit and strategy.position_size != 0
    strategy.close_all(comment = "Trend flip")
PINE
echo "wrote $out ($(wc -l < "$out") lines)"
