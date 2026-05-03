from app.pipeline.analysis_utils import sanitize_text_field, sanitize_public_analysis_text, _is_code_like_text


INVESTING_COM_JS = '{const a=e.bidRequestsCount||0; const t=Object.keys(n).map((function(e){return n[e].bidderCode})),o=r.bidsReceived.length-e,i=r.cpmGreedyType,p=n.code||"unknown";return{auctionId:r.auctionId,bidderCode:p,cpm:e.cpm,status:e.status}}'

PREBID_JS = 'var pbjs=pbjs||{};pbjs.que=pbjs.que||[];pbjs.bidderSettings={standard:{adserverTargeting:[{key:"hb_bidder",val:function(bidResponse){return bidResponse.bidderCode}},{key:"hb_adid",val:function(bidResponse){return bidResponse.adId}}]}}};'

WINDOW_DOCUMENT_JS = 'window.__INITIAL_STATE__={"user":{"id":null,"loggedIn":false}};document.addEventListener("DOMContentLoaded",function(){console.log("ready")});'

LOCAL_STORAGE_JS = 'localStorage.setItem("consent",JSON.stringify({ad:true,analytics:false}));if(!localStorage.getItem("uid")){localStorage.setItem("uid",crypto.randomUUID())}'

GOOGLETAG_JS = 'googletag.cmd.push(function(){googletag.defineSlot("/1234567/leaderboard",[[728,90]],"div-gpt-ad-123456").addService(googletag.pubads());googletag.enableServices()});'

TCF_API_JS = '__tcfapi("getTCData",2,function(tcData,success){console.log(tcData.purpose.consents)})'

WEBPACK_JS = 'webpackJsonp.push([["chunk-vendor"],{"0ca9":function(e,t,n){"use strict";n.r(t);var r=n("e628"),o=n.n(r)}}])'

ARTICLE_WITH_JS = '<p>Hood reported strong Q1 earnings, beating analyst estimates for revenue.</p><script>var adUnit="/1234567/home";googletag.cmd.push(function(){googletag.pubads().setTargeting("stock","hood")});</script><p>The company raised its forward guidance.</p>'

CLEAN_ARTICLE = "Hood reported strong Q1 earnings, beating analyst estimates for revenue. The company raised its forward guidance."

JSON_LD_ARTICLE = '<script type="application/ld+json">{"@type":"NewsArticle","headline":"Hood earnings beat"}</script><p>Hood reported strong Q1 earnings, beating analyst estimates for revenue.</p>'

CONSENT_JS = 'Cookie Settings We use cookies to improve your experience. Accept all cookies to continue. Manage cookies Privacy Policy Terms of Service'

SHORT_CONSENT = 'Accept all cookies'


class TestIsCodeLikeText:
    def test_investing_js_detected(self):
        assert _is_code_like_text(INVESTING_COM_JS) is True

    def test_prebid_detected(self):
        assert _is_code_like_text(PREBID_JS) is True

    def test_window_document_detected(self):
        assert _is_code_like_text(WINDOW_DOCUMENT_JS) is True

    def test_local_storage_detected(self):
        assert _is_code_like_text(LOCAL_STORAGE_JS) is True

    def test_googletag_detected(self):
        assert _is_code_like_text(GOOGLETAG_JS) is True

    def test_tcf_api_detected(self):
        assert _is_code_like_text(TCF_API_JS) is True

    def test_webpack_detected(self):
        assert _is_code_like_text(WEBPACK_JS) is True

    def test_clean_article_not_detected(self):
        assert _is_code_like_text(CLEAN_ARTICLE) is False

    def test_empty_string(self):
        assert _is_code_like_text("") is False

    def test_single_const_not_flagged(self):
        assert _is_code_like_text("The stock was const during trading.") is False

    def test_const_with_brace_semicolon(self):
        assert _is_code_like_text("const a={bid:0};return a") is True


class TestSanitizeTextField:
    def test_clean_article_passes_through(self):
        result = sanitize_text_field(CLEAN_ARTICLE)
        assert "strong Q1 earnings" in result
        assert "raised its forward guidance" in result

    def test_investing_js_returns_fallback(self):
        result = sanitize_text_field(INVESTING_COM_JS, fallback="Summary unavailable")
        assert result == "Summary unavailable"

    def test_investing_js_default_fallback_empty(self):
        result = sanitize_text_field(INVESTING_COM_JS)
        assert result == ""

    def test_prebid_js_returns_fallback(self):
        result = sanitize_text_field(PREBID_JS, fallback="Summary unavailable")
        assert result == "Summary unavailable"

    def test_html_article_stripped_to_text(self):
        result = sanitize_text_field(ARTICLE_WITH_JS)
        assert "googletag" not in result
        assert "adUnit" not in result
        assert "Hood reported strong Q1 earnings" in result
        assert "raised its forward guidance" in result

    def test_json_ld_stripped(self):
        result = sanitize_text_field(JSON_LD_ARTICLE)
        assert "application/ld+json" not in result
        assert "@type" not in result
        assert "Hood reported strong Q1 earnings" in result

    def test_window_js_returns_fallback(self):
        result = sanitize_text_field(WINDOW_DOCUMENT_JS, fallback="Article unavailable")
        assert result == "Article unavailable"

    def test_googletag_js_returns_fallback(self):
        result = sanitize_text_field(GOOGLETAG_JS)
        assert result == ""

    def test_none_returns_fallback(self):
        assert sanitize_text_field(None, fallback="No data") == "No data"

    def test_empty_returns_fallback(self):
        assert sanitize_text_field("", fallback="No data") == "No data"

    def test_short_consent_boilerplate_suppressed(self):
        result = sanitize_text_field(CONSENT_JS, fallback="")
        assert result == ""

    def test_article_with_some_consent_text_preserved(self):
        mixed = "Hood reported strong Q1 earnings. Cookie Settings are available on our platform."
        result = sanitize_text_field(mixed, fallback="")
        assert len(result) > 50
        assert "Hood reported" in result

    def test_html_entities_decoded(self):
        result = sanitize_text_field("Revenue&nbsp;was&nbsp;$1.2B&amp;nbsp;above&nbsp;expectations")
        assert "Revenue was" in result
        assert "&nbsp;" not in result

    def test_consent_boilerplate_short_text_rejected(self):
        result = sanitize_text_field(SHORT_CONSENT, fallback="")
        assert result == ""

    def test_real_title_preserved(self):
        title = "Robinhood Reports Q1 Revenue Beat, Raises Forward Guidance"
        result = sanitize_text_field(title, fallback="No title")
        assert result == title

    def test_real_summary_preserved(self):
        summary = "Robinhood reported Q1 revenue of $655 million, beating analyst estimates of $611 million. The company raised its full-year guidance citing strong user growth."
        result = sanitize_text_field(summary, fallback="No summary")
        assert "Robinhood reported" in result
        assert "Q1 revenue" in result

    def test_html_stripped_from_summary(self):
        html_summary = "<p>Robinhood reported Q1 revenue of $655 million.</p>"
        result = sanitize_text_field(html_summary, fallback="")
        assert result == "Robinhood reported Q1 revenue of $655 million."


class TestSanitizePublicAnalysisTextWithCodeDetection:
    def test_dict_with_js_values_cleaned(self):
        payload = {
            "title": "Robinhood Q1 Earnings Beat",
            "summary": INVESTING_COM_JS,
            "long_analysis": CLEAN_ARTICLE,
        }
        result = sanitize_public_analysis_text(payload)
        assert result["title"] == "Robinhood Q1 Earnings Beat"
        assert result["summary"] == ""
        assert "Hood reported" in result["long_analysis"]

    def test_nested_list_with_js_cleaned(self):
        payload = {
            "key_implications": [
                "Revenue beat estimates by 7%",
                PREBID_JS,
                "Guidance raised for FY2025",
            ]
        }
        result = sanitize_public_analysis_text(payload)
        assert result["key_implications"][0] == "Revenue beat estimates by 7%"
        assert result["key_implications"][1] == ""
        assert result["key_implications"][2] == "Guidance raised for FY2025"

    def test_html_in_driver_cards_cleaned(self):
        card = {
            "title": "<b>Revenue beat</b> estimates",
            "summary": ARTICLE_WITH_JS,
        }
        result = sanitize_public_analysis_text(card)
        assert result["title"] == "Revenue beat estimates"
        assert "googletag" not in result["summary"]
        assert "Hood reported strong" in result["summary"]

    def test_event_analyses_with_investing_com_garbage(self):
        events = [
            {"title": "Robinhood Q1 Beat", "summary": CLEAN_ARTICLE, "long_analysis": CLEAN_ARTICLE},
            {"title": INVESTING_COM_JS[:200], "summary": INVESTING_COM_JS, "long_analysis": INVESTING_COM_JS},
            {"title": "Guidance Raised", "summary": "The company raised forward guidance.", "long_analysis": "Details here."},
        ]
        result = sanitize_public_analysis_text(events)
        assert result[0]["title"] == "Robinhood Q1 Beat"
        assert result[1]["title"] == ""
        assert result[1]["summary"] == ""
        assert result[1]["long_analysis"] == ""
        assert result[2]["title"] == "Guidance Raised"

    def test_existing_word_replacements_still_work(self):
        payload = {"summary": "This is a full_body read. Coverage is thin. Sentiment is mixed."}
        result = sanitize_public_analysis_text(payload)
        assert "full_body" not in result["summary"]
        assert "coverage" not in result["summary"].lower()

    def test_supporting_evidence_with_js_cleaned(self):
        evidence = {
            "title": "Robinhood earnings report",
            "summary": GOOGLETAG_JS,
        }
        result = sanitize_public_analysis_text(evidence)
        assert result["title"] == "Robinhood earnings report"
        assert result["summary"] == ""


class TestNewsNormalizerIntegration:
    def test_normalize_investing_js_article(self):
        from app.pipeline.news_normalizer import normalize_news_item
        article = {
            "title": "Robinhood Q1 Earnings Beat Analyst Estimates",
            "summary": INVESTING_COM_JS,
            "body": INVESTING_COM_JS,
            "url": "https://www.investing.com/news/hood-q1",
            "source": "Investing.com",
            "published_at": "2026-05-01T10:00:00Z",
        }
        result = normalize_news_item(article, "finnhub")
        assert result["title"] == "Robinhood Q1 Earnings Beat Analyst Estimates"
        # JS summaries fall back to title when detected as code
        assert result["summary"] == "Robinhood Q1 Earnings Beat Analyst Estimates"
        assert result["body"] == "Robinhood Q1 Earnings Beat Analyst Estimates"

    def test_normalize_clean_article(self):
        from app.pipeline.news_normalizer import normalize_news_item
        article = {
            "title": "Robinhood Q1 Earnings Beat",
            "summary": "Revenue of $655M beat estimates of $611M.",
            "body": "Robinhood reported Q1 revenue of $655 million, beating analyst estimates.",
            "url": "https://www.reuters.com/hood-q1",
            "source": "Reuters",
            "published_at": "2026-05-01T10:00:00Z",
        }
        result = normalize_news_item(article, "finnhub")
        assert result["title"] == "Robinhood Q1 Earnings Beat"
        assert "$655M" in result["summary"]

    def test_evidence_quality_js_body_is_title_only(self):
        from app.pipeline.news_normalizer import normalize_news_item, _evidence_quality
        title = "Robinhood Q1 Earnings Beat"
        js_body = INVESTING_COM_JS
        js_summary = PREBID_JS
        clean_title = "Robinhood Q1 Earnings Beat"
        quality = _evidence_quality(clean_title, js_body, js_summary, raw_body=js_body)
        assert quality in ("title_only", "headline_summary")