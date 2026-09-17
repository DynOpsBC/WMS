/// <summary>
/// Zones (alanlar) of a location for the terminal's label flow (DKÇ, 17 Eyl
/// 2026): the operator picks a location, then a zone such as AKILLI DOL, and
/// prints the labels of every bin under it. The bins API only carries the zone
/// CODE, so the description ("AKILLI DOLAP SİSTEMİ") is read from here and
/// printed on the label.
/// </summary>
page 72327 "DOPSWHS Zone API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'zone';
    EntitySetName = 'zones';
    SourceTable = Zone;
    DelayedInsert = true;
    ODataKeyFields = "Location Code", Code;
    Editable = false;
    Extensible = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; }
                field(code; Rec.Code) { Caption = 'code'; }
                field(description; Rec.Description) { Caption = 'description'; }
                field(binTypeCode; Rec."Bin Type Code") { Caption = 'binTypeCode'; }
                field(warehouseClassCode; Rec."Warehouse Class Code") { Caption = 'warehouseClassCode'; }
                field(zoneRanking; Rec."Zone Ranking") { Caption = 'zoneRanking'; }
            }
        }
    }

    [ServiceEnabled]
    procedure printLabel(printerId: Code[50]; copies: Integer)
    var
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
    begin
        Dispatcher.PrintZoneLabel(Rec, printerId, copies);
    end;
}
