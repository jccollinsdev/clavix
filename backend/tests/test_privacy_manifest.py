import plistlib
from pathlib import Path


def test_privacy_manifest_declares_current_collection_and_valid_purposes():
    manifest_path = (
        Path(__file__).resolve().parents[2]
        / "ios"
        / "Clavis"
        / "Resources"
        / "PrivacyInfo.xcprivacy"
    )
    with manifest_path.open("rb") as handle:
        manifest = plistlib.load(handle)

    declarations = {
        item["NSPrivacyCollectedDataType"]: item
        for item in manifest["NSPrivacyCollectedDataTypes"]
    }
    expected = {
        "NSPrivacyCollectedDataTypeEmailAddress",
        "NSPrivacyCollectedDataTypeName",
        "NSPrivacyCollectedDataTypeUserID",
        "NSPrivacyCollectedDataTypeOtherFinancialInfo",
        "NSPrivacyCollectedDataTypeDeviceID",
        "NSPrivacyCollectedDataTypeProductInteraction",
        "NSPrivacyCollectedDataTypePurchaseHistory",
        "NSPrivacyCollectedDataTypeOtherDataTypes",
    }
    assert expected <= declarations.keys()
    assert manifest["NSPrivacyTracking"] is False

    for declaration in declarations.values():
        assert declaration["NSPrivacyCollectedDataTypeTracking"] is False
        assert declaration["NSPrivacyCollectedDataTypePurposes"]
        assert all(
            purpose.startswith("NSPrivacyCollectedDataTypePurpose")
            for purpose in declaration["NSPrivacyCollectedDataTypePurposes"]
        )
