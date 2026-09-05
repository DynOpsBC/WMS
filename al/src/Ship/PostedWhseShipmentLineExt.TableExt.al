tableextension 72405 "DOPSWHS Posted Whse Shpt Line" extends "Posted Whse. Shipment Line"
{
    fields
    {
        field(72405; "LP No."; Code[20])
        {
            Caption = 'LP No.';
            DataClassification = CustomerContent;
            TableRelation = "DOPSWHS LP Header"."No.";
        }
        // Standard posting copies source field 72406 (LP No., Code[20]).
        // Retain this installed column for upgrade, but widen it so a 20-char
        // LP cannot fail TransferFields before the propagation subscriber runs.
        field(72406; "DOPSWHS Legacy SSCC"; Code[20])
        {
            Caption = 'SSCC (Legacy)';
            DataClassification = CustomerContent;
            ObsoleteState = Pending;
            ObsoleteReason = 'Use SSCC field 72407, matching Warehouse Shipment Line. Existing SSCC values are migrated on upgrade.';
            ObsoleteTag = '1.14.1.29';
        }
        field(72407; "SSCC"; Code[18])
        {
            Caption = 'SSCC';
            DataClassification = CustomerContent;
        }
    }
}
