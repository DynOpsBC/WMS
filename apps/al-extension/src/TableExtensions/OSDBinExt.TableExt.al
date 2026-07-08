tableextension 50029001 "OSD Bin Ext" extends Bin
{
    fields
    {
        field(50029000; "WMS Pickable"; Boolean) { Caption = 'WMS Pickable'; DataClassification = CustomerContent; InitValue = true; }
        field(50029001; "WMS Receivable"; Boolean) { Caption = 'WMS Receivable'; DataClassification = CustomerContent; InitValue = true; }
        field(50029002; "WMS Quarantine"; Boolean) { Caption = 'WMS Quarantine'; DataClassification = CustomerContent; }
        field(50029003; "WMS Bin Ranking"; Integer) { Caption = 'WMS Bin Ranking'; DataClassification = CustomerContent; }
    }
}
