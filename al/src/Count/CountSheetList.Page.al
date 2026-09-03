page 72074 "DOPSWHS Count Sheet List"
{
    Caption = 'Count Sheets';
    PageType = List;
    SourceTable = "DOPSWHS Count Sheet Header";
    ApplicationArea = All;
    UsageCategory = Lists;
    CardPageId = "DOPSWHS Count Sheet Card";

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field("No."; Rec."No.") { ApplicationArea = All; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; }
                field("Zone Filter"; Rec."Zone Filter") { ApplicationArea = All; }
                field(Mode; Rec.Mode) { ApplicationArea = All; }
                field(Status; Rec.Status) { ApplicationArea = All; }
                field("V2 Scan Mode"; Rec."V2 Scan Mode") { ApplicationArea = All; Editable = false; }
                field("Created DateTime"; Rec."Created DateTime") { ApplicationArea = All; }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(NewCountSheet)
            {
                Caption = 'New';
                ApplicationArea = All;
                Image = NewDocument;
                RunObject = page "DOPSWHS Count Sheet Card";
                RunPageMode = Create;
            }
            action(OpenCard)
            {
                Caption = 'Open Card';
                ApplicationArea = All;
                Image = EditLines;
                RunObject = page "DOPSWHS Count Sheet Card";
                RunPageLink = "No." = field("No.");
            }
            action(Post)
            {
                Caption = 'Post';
                ApplicationArea = All;
                Image = Post;
                trigger OnAction()
                var
                    CountMgmt: Codeunit "DOPSWHS Count Mgmt";
                begin
                    CountMgmt.PostSheet(Rec."No.");
                    CurrPage.Update(false);
                end;
            }
            action(GenerateLines)
            {
                Caption = 'Satırları Üret';
                ApplicationArea = All;
                Image = CalculateLines;
                trigger OnAction()
                var
                    CountMgmt: Codeunit "DOPSWHS Count Mgmt";
                    LinesCreated: Integer;
                begin
                    LinesCreated := CountMgmt.GenerateLines(Rec."No.");
                    CurrPage.Update(false);
                    Message('%1 sayım satırı oluşturuldu.', LinesCreated);
                end;
            }
            action(ConvertToV2)
            {
                Caption = 'V2 Sayımına Çevir';
                ToolTip = 'Satırı olmayan açık belgeyi Sayım V2 (terminalde yalnız barkod okutarak sayım) moduna alır. Terminaldeki Sayım V2 listesinde görünür.';
                ApplicationArea = All;
                Image = BarCode;
                trigger OnAction()
                var
                    CountMgmt: Codeunit "DOPSWHS Count Mgmt";
                begin
                    if Rec."No." = '' then
                        exit; // boş liste: seçili belge yok
                    if Rec."V2 Scan Mode" then begin
                        Message(AlreadyV2Msg, Rec."No.");
                        exit;
                    end;
                    CountMgmt.PrepareV2(Rec."No.");
                    CurrPage.Update(false);
                    Message(ConvertedToV2Msg, Rec."No.");
                end;
            }
        }
    }

    var
        AlreadyV2Msg: Label '%1 sayım belgesi zaten Sayım V2 modunda.', Comment = '%1 count sheet no';
        ConvertedToV2Msg: Label '%1 sayım belgesi Sayım V2 moduna alındı.', Comment = '%1 count sheet no';
}
