page 72098 "DOPSWHS Pick Board Page"
{
    PageType = Card;
    Caption = 'Pick Board';
    ApplicationArea = All;
    UsageCategory = Tasks;  // searchable in "Tell me"

    layout
    {
        area(Content)
        {
            usercontrol(Board; "DOPSWHS Pick Board")
            {
                ApplicationArea = All;

                trigger ControlReady()
                begin
                    CurrPage.Board.SetLocale(Format(GlobalLanguage()));
                    CurrPage.Board.SetData(BoardData.BuildPickBoardJson());
                end;

                trigger Reassign(PickNo: Code[20]; UserId: Code[50])
                var
                    Pick: Record "Warehouse Activity Header";
                    PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
                begin
                    if Pick.Get(Pick.Type::Pick, PickNo) then
                        PickMgmt.ReassignPick(Pick, UserId, 'Pick Board drag-drop');
                    CurrPage.Board.SetData(BoardData.BuildPickBoardJson());
                end;

                trigger RequestRefresh()
                begin
                    CurrPage.Board.SetData(BoardData.BuildPickBoardJson());
                end;
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(Refresh)
            {
                ApplicationArea = All;
                Caption = 'Refresh';
                Image = Refresh;
                trigger OnAction()
                begin
                    CurrPage.Board.SetData(BoardData.BuildPickBoardJson());
                end;
            }
        }
    }

    var
        BoardData: Codeunit "DOPSWHS Board Data";
}
