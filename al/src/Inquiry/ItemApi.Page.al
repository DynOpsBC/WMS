page 72086 "DOPSWHS Item API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'item';
    EntitySetName = 'items';
    SourceTable = Item;
    DelayedInsert = true;
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(no; Rec."No.") { Caption = 'no'; }
                field(description; Rec.Description) { Caption = 'description'; }
                field(baseUnitOfMeasure; Rec."Base Unit of Measure") { Caption = 'baseUnitOfMeasure'; }
                field(itemCategoryCode; Rec."Item Category Code") { Caption = 'itemCategoryCode'; }
                field(blocked; Rec.Blocked) { Caption = 'blocked'; }
                field(defaultLpTemplateCode; Rec."DOPSWHS Default LP Template") { Caption = 'defaultLpTemplateCode'; }
                field(defaultPrintRuleCode; Rec."DOPSWHS Default Print Rule") { Caption = 'defaultPrintRuleCode'; }
            }
        }
    }
}
