page 72087 "DOPSWHS Bin API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'bin';
    EntitySetName = 'bins';
    SourceTable = Bin;
    DelayedInsert = true;
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; }
                field(code; Rec.Code) { Caption = 'code'; }
                field(description; Rec.Description) { Caption = 'description'; }
                field(zoneCode; Rec."Zone Code") { Caption = 'zoneCode'; }
                field(binTypeCode; Rec."Bin Type Code") { Caption = 'binTypeCode'; }
                field(blockMovement; Rec."Block Movement") { Caption = 'blockMovement'; }
            }
        }
    }
}
