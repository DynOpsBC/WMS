page 72071 "DOPSWHS LP Template List"
{
    Caption = 'LP Templates';
    PageType = List;
    SourceTable = "DOPSWHS LP Template";
    ApplicationArea = All;
    UsageCategory = Administration;

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                field("Code"; Rec."Code") { ApplicationArea = All; }
                field(Description; Rec.Description) { ApplicationArea = All; }
                field("Default Tare Weight kg"; Rec."Default Tare Weight kg") { ApplicationArea = All; }
                field("Default Length cm"; Rec."Default Length cm") { ApplicationArea = All; }
                field("Default Width cm"; Rec."Default Width cm") { ApplicationArea = All; }
                field("Default Height cm"; Rec."Default Height cm") { ApplicationArea = All; }
                field("Max Weight kg"; Rec."Max Weight kg") { ApplicationArea = All; }
                field("Container Kind"; Rec."Container Kind") { ApplicationArea = All; ToolTip = 'Palet / koli / kutu / çuval. Etiket tasarımını ve paketleme listesindeki sayaçları belirler.'; }
                field("Label Design"; Rec."Label Design") { ApplicationArea = All; ToolTip = '"Kaba göre" kabın türüne uygun ZPL etiketi basar; "Rapor (PDF)" Label Report ID raporunu belge yazıcısından basar.'; }
                field("Label Includes Contents"; Rec."Label Includes Contents") { ApplicationArea = All; ToolTip = 'Açık: etikette LP içeriği (madde, lot, miktar; iç katmanlar) listelenir. Kapalı: yalnız LP kimliği ve özet.'; }
                field("Label Copies"; Rec."Label Copies") { ApplicationArea = All; ToolTip = 'Tek "Etiket Yazdır" ile basılacak kopya sayısı (0 = 1).'; }
                field("Label Report ID"; Rec."Label Report ID") { ApplicationArea = All; }
                field("No. Series"; Rec."No. Series") { ApplicationArea = All; }
                field("Allow Mixed Items"; Rec."Allow Mixed Items") { ApplicationArea = All; }
                field("Allow Mixed Lots"; Rec."Allow Mixed Lots") { ApplicationArea = All; }
            }
        }
    }
}
