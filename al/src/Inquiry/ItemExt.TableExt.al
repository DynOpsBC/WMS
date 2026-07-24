tableextension 72400 "DOPSWHS Item Ext" extends Item
{
    fields
    {
        field(72400; "DOPSWHS Default LP Template"; Code[20])
        {
            Caption = 'Default LP Template Code';
            DataClassification = CustomerContent;
        }
        field(72401; "DOPSWHS Default Print Rule"; Code[20])
        {
            Caption = 'Default Print Rule Code';
            DataClassification = CustomerContent;
        }
        field(72402; "DOPSWHS QC Required"; Boolean)
        {
            Caption = 'Quality Control Required on Receipt';
            DataClassification = CustomerContent;
            ToolTip = 'Açıkken, bu maddenin mal kabulünde otomatik olarak bir Quality Order açılır ve (Setup''ta tanımlıysa) karantina bin''ine yönlendirilir. Onay/red verilene kadar Pick/Movement bu LP''yi bloklar.';
        }
    }
}
