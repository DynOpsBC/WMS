tableextension 50101 "WMS Bin Ext" extends Bin
{
    fields
    {
        field(50100; "WMS Pickable"; Boolean) { Caption = 'WMS Pickable'; DataClassification = CustomerContent; InitValue = true; }
        field(50101; "WMS Receivable"; Boolean) { Caption = 'WMS Receivable'; DataClassification = CustomerContent; InitValue = true; }
        field(50102; "WMS Quarantine"; Boolean) { Caption = 'WMS Quarantine'; DataClassification = CustomerContent; }
        field(50103; "WMS Bin Ranking"; Integer) { Caption = 'WMS Bin Ranking'; DataClassification = CustomerContent; }
    }
}
