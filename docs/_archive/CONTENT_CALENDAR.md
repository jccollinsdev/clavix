# Sansar Content — Week of May 5–10, 2026

---

## Post 1: The UI Lie

**Hook:** My app was showing users fake data.

**Body:**
I built this entire backend system that generates risk scores for stocks. A to F. Clean. Structured.

But the UI? It was showing stale placeholders, wrong labels, and random fallback text that meant nothing.

Users would see "Strong momentum" when the backend said "Severe risk."

That’s not a bug. That’s a lie.

This week I’m stripping every piece of UI that doesn’t match the backend exactly. If the data says C, the UI says C. No translation layer. No pretty wrapping. Just truth.

**CTA:** Follow if you want to see what happens when you stop tolerating broken UI.

---

## Post 2: Why My App Was Dying Every Morning

**Hook:** Every day at 7am, my app tried to run a 25-minute analysis. It failed 40% of the time.

**Body:**
The backfill system. I built it to refresh stock data every morning. S&P 500. All 500 tickers.

But it was doing full live analysis on every open. 25 minutes. Rate limits. Timeout crashes.

The fix? Stop analyzing. Start *fetching*.

The analysis already happened. It’s stored. The app should just pull it. 200ms. Done.

I spent 3 days rewriting the whole data layer so the app trusts what’s already computed instead of panicking and re-running everything.

**CTA:** This is what happens when you stop building features and start building systems.

---

## Post 3: I Gave Users a Score. I Couldn’t Explain It.

**Hook:** My app says your stock is a C+. But if you tap the C+, nothing happens.

**Body:**
Risk dimension bars. I built them. They look great.

Macro exposure: 34. Volatility trend: 67. Liquidity stress: 12.

But what do those numbers mean? Where did they come from? What news drove them?

Right now: nothing. You just trust it.

This week I’m making every bar tappable. Tap macro exposure → see the exact headlines that moved it. Tap liquidity → see the earnings report that triggered it.

A score without derivation is a guess. I’m done guessing.

**CTA:** Would you trust a credit rating you can’t inspect?

---

## Post 4: The 21-Commit Day

**Hook:** I pushed 21 commits in one day. My GitHub looks like I hacked NASA.

**Body:**
April 27. I sat down to fix one bug. I fixed 14.

Sticky headers were broken. Hero sections had dead labels. Risk dimensions showed 0 when they should’ve showed real scores. Driver cards had raw RSS headlines as titles.

I don’t work in sprints. I work in bursts.

When I see a crack, I can’t stop until the whole wall is solid. That’s why this app is taking 6 months instead of 6 weeks.

Because I won’t ship something that feels wrong.

**CTA:** Are you a sprinter or a burster?

---

## Post 5: Stop Showing. Start Proving.

**Hook:** Every finance app gives you a score. Almost none prove how they got it.

**Body:**
Simply Wall St does something beautiful. They show you the *path*.

You see a snowflake. You tap it. You see the underlying ratios. You see the trend lines. You see why.

My app gives you a grade: A, B, C, D, F.

But until this week, tapping that grade did nothing.

Now? You tap the macro bar → you see the Fed decision that moved it. You tap valuation → you see the P/E expansion that triggered the warning.

Scores without proof are marketing. Scores with proof are intelligence.

**CTA:** Which one does your app give you?

---

## Post 6: Sunday Deadline — What I’m Actually Fixing

**Hook:** By Sunday, this app either fetches cleanly or I delete it.

**Body:**
Three things:

1. UI cleanup — every label, every card, every screen matches the backend data exactly. No drift.
2. Backfill → fetch — the app stops trying to live-analyze on open. It pulls stored data in under a second.
3. Tappable dimensions — every risk bar is inspectable. Every score has a paper trail.

If I can’t finish this by Sunday, I don’t understand my own system well enough to ship it.

And if I don’t understand it, no user will trust it.

**CTA:** What’s your Sunday deadline?

---

*Week: May 5–10, 2026 | Scripts: 6 | Topics: UI cleanup, backfill→fetch, tappable dimensions, build-in-public momentum*
