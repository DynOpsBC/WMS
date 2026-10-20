page 72471 "DOPSWHS Label Layout Lines"
{
    Caption = 'Tasarım Elemanları';
    PageType = ListPart;
    SourceTable = "DOPSWHS Label Layout Line";
    AutoSplitKey = true;
    DelayedInsert = true;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(Enabled; Rec.Enabled) { ApplicationArea = All; ToolTip = 'Kapalı eleman basılmaz.'; }
                field("Element Type"; Rec."Element Type") { ApplicationArea = All; ToolTip = 'Metin/Alan: yazı; Barkod: Code128; QR Kod; Çizgi; Kutu.'; }
                field("X (mm)"; Rec."X (mm)") { ApplicationArea = All; ToolTip = 'Sol kenardan uzaklık (mm).'; }
                field("Y (mm)"; Rec."Y (mm)") { ApplicationArea = All; ToolTip = 'Üst kenardan uzaklık (mm).'; }
                field("Width (mm)"; Rec."Width (mm)") { ApplicationArea = All; }
                field("Height (mm)"; Rec."Height (mm)") { ApplicationArea = All; }
                field("Font Height (mm)"; Rec."Font Height (mm)") { ApplicationArea = All; }
                field(Alignment; Rec.Alignment) { ApplicationArea = All; }
                field("Source Field"; Rec."Source Field")
                {
                    ApplicationArea = All;

                    trigger OnLookup(var Text: Text): Boolean
                    var
                        LayoutHeader: Record "DOPSWHS Label Layout";
                        LayoutFields: Codeunit "DOPSWHS Label Layout Fields";
                        Choice: Integer;
                        FieldKeys: List of [Text];
                    begin
                        if not LayoutHeader.Get(Rec."Layout Code") then
                            exit(false);
                        LayoutFields.KeysFor(LayoutHeader."Label Kind", FieldKeys);
                        Choice := StrMenu(LayoutFields.KeyList(LayoutHeader."Label Kind"), 0, 'Alan seçin');
                        if Choice = 0 then
                            exit(false);
                        Text := FieldKeys.Get(Choice);
                        exit(true);
                    end;
                }
                field("Static Text"; Rec."Static Text") { ApplicationArea = All; }
                field(Prefix; Rec.Prefix) { ApplicationArea = All; }
                field(Suffix; Rec.Suffix) { ApplicationArea = All; }
                field("Max Lines"; Rec."Max Lines") { ApplicationArea = All; }
                field("Fit to Width"; Rec."Fit to Width") { ApplicationArea = All; }
                field("Min Font Height (mm)"; Rec."Min Font Height (mm)") { ApplicationArea = All; Visible = false; }
                field("Font Width (mm)"; Rec."Font Width (mm)") { ApplicationArea = All; Visible = false; }
                field(Inverted; Rec.Inverted) { ApplicationArea = All; }
                field("Show Text"; Rec."Show Text") { ApplicationArea = All; }
                field("Thickness (mm)"; Rec."Thickness (mm)") { ApplicationArea = All; Visible = false; }
            }
        }
    }
}
