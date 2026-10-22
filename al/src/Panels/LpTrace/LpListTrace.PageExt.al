pageextension 72394 "DOPSWHS LP List Trace" extends "DOPSWHS LP List"
{
    actions
    {
        addfirst(Processing)
        {
            action(DOPSWHSLpTrace)
            {
                ApplicationArea = All;
                Caption = 'İzlenebilirlik';
                ToolTip = 'Seçili LP''nin içeriğini, hareket geçmişini, bağlı madde/ambar girişlerini ve belgelerini tek ekranda gösterir.';
                Image = Trace;
                Promoted = true;
                PromotedCategory = Process;

                trigger OnAction()
                var
                    TracePage: Page "DOPSWHS LP Trace";
                begin
                    TracePage.SetSearch(Rec."No.");
                    TracePage.Run();
                end;
            }
        }
    }
}
