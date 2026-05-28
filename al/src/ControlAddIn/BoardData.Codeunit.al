codeunit 72258 "DOPSWHS Board Data"
{
    // Builds the JSON payloads the web SPAs (Pick Board, LP Browser) consume, and exposes the
    // mutating helpers their drag-drop / context actions call back into.
    Access = Public;

    /// <summary>{"picks":[{no,sourceNo,assignedUserId,status,percentComplete,dueDate}]} from open picks.</summary>
    procedure BuildPickBoardJson(): Text
    var
        Pick: Record "Warehouse Activity Header";
        Json: TextBuilder;
        First: Boolean;
    begin
        Json.Append('{"picks":[');
        First := true;
        Pick.SetRange(Type, Pick.Type::Pick);
        if Pick.FindSet() then
            repeat
                if not First then Json.Append(',');
                First := false;
                Json.Append(BuildPickObject(Pick));
            until Pick.Next() = 0;
        Json.Append(']}');
        exit(Json.ToText());
    end;

    local procedure BuildPickObject(var Pick: Record "Warehouse Activity Header"): Text
    var
        PickLine: Record "Warehouse Activity Line";
        SourceNo: Code[20];
        DueDate: Date;
        TotalQty: Decimal;
        HandledQty: Decimal;
        Pct: Integer;
        StatusText: Text;
    begin
        PickLine.SetRange("Activity Type", Pick.Type);
        PickLine.SetRange("No.", Pick."No.");
        if PickLine.FindSet() then
            repeat
                if SourceNo = '' then begin
                    SourceNo := PickLine."Source No.";
                    DueDate := PickLine."Due Date";
                end;
                TotalQty += PickLine.Quantity;
                HandledQty += PickLine."Qty. Handled";
            until PickLine.Next() = 0;
        if TotalQty <> 0 then
            Pct := Round(HandledQty / TotalQty * 100, 1);
        if Pick."Assigned User ID" = '' then StatusText := 'Open'
        else if Pct >= 100 then StatusText := 'Done'
        else if Pct > 0 then StatusText := 'InProgress'
        else StatusText := 'Open';

        exit(StrSubstNo(
            '{"no":"%1","sourceNo":"%2","assignedUserId":"%3","status":"%4","percentComplete":%5,"dueDate":"%6"}',
            Esc(Pick."No."), Esc(SourceNo), Esc(Pick."Assigned User ID"), StatusText, Pct,
            Format(DueDate, 0, '<Year4>-<Month,2>-<Day,2>')));
    end;

    /// <summary>Flat LP array (the SPA nests by parentLpNo): {"value":[{no,parentLpNo,binCode,status}]}.</summary>
    procedure BuildLpTreeJson(): Text
    var
        LP: Record "DOPSWHS LP Header";
        Json: TextBuilder;
        First: Boolean;
    begin
        Json.Append('{"value":[');
        First := true;
        LP.SetCurrentKey("No.");
        if LP.FindSet() then
            repeat
                if not First then Json.Append(',');
                First := false;
                Json.Append(StrSubstNo(
                    '{"no":"%1","parentLpNo":"%2","binCode":"%3","status":"%4"}',
                    Esc(LP."No."), Esc(LP."Parent LP No."), Esc(LP."Bin Code"), Format(LP.Status)));
            until LP.Next() = 0;
        Json.Append(']}');
        exit(Json.ToText());
    end;

    /// <summary>LP Browser "Move to Bin": update the LP's bin (simple bin move).</summary>
    procedure MoveLpToBin(LpNo: Code[20]; BinCode: Code[20])
    var
        LP: Record "DOPSWHS LP Header";
    begin
        if not LP.Get(LpNo) then exit;
        LP.Validate("Bin Code", BinCode);
        LP."Last Modified DateTime" := CurrentDateTime();
        LP.Modify(true);
    end;

    /// <summary>LP Browser drag-nest: nest child LP under parent via the Nest Manager.</summary>
    procedure NestLp(ChildLpNo: Code[20]; ParentLpNo: Code[20])
    var
        ChildLP: Record "DOPSWHS LP Header";
        ParentLP: Record "DOPSWHS LP Header";
        NestMgr: Codeunit "DOPSWHS LP Nest Manager";
    begin
        if not ChildLP.Get(ChildLpNo) then exit;
        if not ParentLP.Get(ParentLpNo) then exit;
        NestMgr.Nest(ChildLP, ParentLP);
    end;

    /// <summary>LP Browser print action.</summary>
    procedure PrintLpLabel(LpNo: Code[20]; PrinterId: Code[50])
    var
        LP: Record "DOPSWHS LP Header";
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
    begin
        if not LP.Get(LpNo) then exit;
        Dispatcher.PrintLPLabel(LP, PrinterId, 1);
    end;

    local procedure Esc(Value: Text): Text
    begin
        Value := Value.Replace('\', '\\');
        Value := Value.Replace('"', '\"');
        exit(Value);
    end;
}
