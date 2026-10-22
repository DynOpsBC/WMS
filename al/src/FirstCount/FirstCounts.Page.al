page 72002 "DOPSWHS First Counts"
{
    Caption = 'İlk Sayımlar';
    PageType = List;
    ApplicationArea = All;
    UsageCategory = Tasks;
    SourceTable = "DOPSWHS First Count Header";
    SourceTableView = sorting("Created DateTime") order(descending);
    Editable = false;
    AdditionalSearchTerms = 'ilk sayım, first count, madde sayımı';

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field("No."; Rec."No.") { ApplicationArea = All; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; }
                field(Status; Rec.Status) { ApplicationArea = All; }
                field("Line Count"; Rec."Line Count") { ApplicationArea = All; }
                field("Created By"; Rec."Created By") { ApplicationArea = All; }
                field("Created DateTime"; Rec."Created DateTime") { ApplicationArea = All; }
                field("Posted DateTime"; Rec."Posted DateTime") { ApplicationArea = All; }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(Lines)
            {
                Caption = 'Satırlar';
                ApplicationArea = All;
                Image = AllLines;
                RunObject = page "DOPSWHS First Count Lines";
                RunPageLink = "Count No." = field("No.");
            }
            action(PostCount)
            {
                Caption = 'Stoğa İşle';
                ApplicationArea = All;
                Image = PostOrder;

                trigger OnAction()
                var
                    FirstCountMgmt: Codeunit "DOPSWHS First Count Mgmt";
                begin
                    if not Confirm('%1 işlensin mi? Okutulan maddelerin stoğu sayılan adede eşitlenecek.', false, Rec."No.") then
                        exit;
                    Message('%1 madde satırında stok düzeltildi.', FirstCountMgmt.PostCount(Rec."No.", CopyStr(UserId(), 1, 50)));
                    CurrPage.Update(false);
                end;
            }
        }
        area(Promoted)
        {
            actionref(Lines_Promoted; Lines) { }
            actionref(PostCount_Promoted; PostCount) { }
        }
    }
}
