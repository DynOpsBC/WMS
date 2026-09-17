/// <summary>
/// Locations for the terminal's lookups (Raf Sorgu location picker, 16 Eyl
/// 2026): code, name and whether bins are mandatory / directed put-away.
/// </summary>
page 72326 "DOPSWHS Location API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'location';
    EntitySetName = 'locations';
    SourceTable = Location;
    DelayedInsert = true;
    ODataKeyFields = Code;
    Editable = false;
    Extensible = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(code; Rec.Code) { Caption = 'code'; }
                field(name; Rec.Name) { Caption = 'name'; }
                field(binMandatory; Rec."Bin Mandatory") { Caption = 'binMandatory'; }
                field(directedPutAwayAndPick; Rec."Directed Put-away and Pick") { Caption = 'directedPutAwayAndPick'; }
                field(useAsInTransit; Rec."Use As In-Transit") { Caption = 'useAsInTransit'; }
            }
        }
    }
}
