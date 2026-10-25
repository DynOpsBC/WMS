// Kitoko (21 Eki 2026): terminal BC'de kayıtlı etiket tasarımlarını listeler
// ve baskıda hangisinin kullanılacağını seçer (items/bins/zones/licensePlates
// printLabelWithLayout). Salt okunur; tasarım BC'de düzenlenir.
/// <summary>
/// Saved label designs (Etiket Tasarımı) for the terminal's design selector.
/// widthMm/heightMm/dpi are the effective values (0 in BC = Setup label size).
/// </summary>
page 72474 "DOPSWHS Label Layout API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'labelLayout';
    EntitySetName = 'labelLayouts';
    SourceTable = "DOPSWHS Label Layout";
    ODataKeyFields = "Code";
    DelayedInsert = true;
    Editable = false;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;
    DataAccessIntent = ReadOnly;
    Extensible = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(code; Rec."Code") { Caption = 'code'; }
                field(description; Rec.Description) { Caption = 'description'; }
                field(labelKind; Rec."Label Kind") { Caption = 'labelKind'; }
                field(widthMm; WidthMm) { Caption = 'widthMm'; }
                field(heightMm; HeightMm) { Caption = 'heightMm'; }
                field(dpi; Dpi) { Caption = 'dpi'; }
                field(active; Rec.Active) { Caption = 'active'; }
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        LayoutEngine: Codeunit "DOPSWHS Label Layout Engine";
    begin
        LayoutEngine.LayoutSizeOf(Rec, WidthMm, HeightMm, Dpi);
    end;

    var
        WidthMm: Decimal;
        HeightMm: Decimal;
        Dpi: Integer;
}
