codeunit 72146 "DOPSWHS First Count Tests"
{
    Subtype = Test;

    [Test]
    procedure SameScanIdDoesNotAddSecondLine()
    var
        Line: Record "DOPSWHS First Count Line";
        FirstCountMgmt: Codeunit "DOPSWHS First Count Mgmt";
        CountNo: Code[20];
        ScanId: Guid;
        First: Integer;
    begin
        Setup('FC-LOC', 'FC-ITEM');
        CountNo := FirstCountMgmt.CreateCount('FC-LOC', 'TESTER');
        ScanId := CreateGuid();
        First := FirstCountMgmt.AddLine(CountNo, ScanId, 'FC-ITEM', '', '', '', '', 5, 'TESTER');
        Assert.AreEqual(First, FirstCountMgmt.AddLine(CountNo, ScanId, 'FC-ITEM', '', '', '', '', 5, 'TESTER'), 'Retry must return the same line.');
        Line.SetRange("Count No.", CountNo);
        Assert.AreEqual(1, Line.Count(), 'Retry must not add a second line.');
    end;

    [Test]
    procedure ZeroQuantityIsRejected()
    var
        FirstCountMgmt: Codeunit "DOPSWHS First Count Mgmt";
        CountNo: Code[20];
    begin
        Setup('FC-LOC', 'FC-ITEM');
        CountNo := FirstCountMgmt.CreateCount('FC-LOC', 'TESTER');
        asserterror FirstCountMgmt.AddLine(CountNo, CreateGuid(), 'FC-ITEM', '', '', '', '', 0, 'TESTER');
    end;

    [Test]
    procedure RepeatedScansOfOneItemShareOneGroup()
    var
        Line: Record "DOPSWHS First Count Line";
        FirstCountMgmt: Codeunit "DOPSWHS First Count Mgmt";
        CountNo: Code[20];
        GroupKey: Text;
    begin
        Setup('FC-LOC', 'FC-ITEM');
        CountNo := FirstCountMgmt.CreateCount('FC-LOC', 'TESTER');
        FirstCountMgmt.AddLine(CountNo, CreateGuid(), 'FC-ITEM', '', '', '', '', 3, 'TESTER');
        FirstCountMgmt.AddLine(CountNo, CreateGuid(), 'FC-ITEM', '', '', '', '', 4, 'TESTER');
        Line.SetRange("Count No.", CountNo);
        Line.FindSet();
        GroupKey := FirstCountMgmt.GroupKeyOf(Line);
        Line.Next();
        Assert.AreEqual(GroupKey, FirstCountMgmt.GroupKeyOf(Line), 'Two scans of one item must be summed in one group.');
        Line.CalcSums("Quantity (Base)");
        Assert.AreEqual(7, Line."Quantity (Base)", 'Counted total must be 7.');
    end;

    local procedure Setup(LocationCode: Code[10]; ItemNo: Code[20])
    var
        Location: Record Location;
        Item: Record Item;
        UnitOfMeasure: Record "Unit of Measure";
        ItemUom: Record "Item Unit of Measure";
    begin
        if not Location.Get(LocationCode) then begin
            Location.Init();
            Location.Code := LocationCode;
            Location.Insert(true);
        end;
        if not UnitOfMeasure.Get('ADET') then begin
            UnitOfMeasure.Init();
            UnitOfMeasure.Code := 'ADET';
            UnitOfMeasure.Insert(true);
        end;
        if not Item.Get(ItemNo) then begin
            Item.Init();
            Item."No." := ItemNo;
            Item.Description := ItemNo;
            Item.Insert(true);
        end;
        if not ItemUom.Get(ItemNo, 'ADET') then begin
            ItemUom.Init();
            ItemUom."Item No." := ItemNo;
            ItemUom.Code := 'ADET';
            ItemUom."Qty. per Unit of Measure" := 1;
            ItemUom.Insert(true);
        end;
        Item."Base Unit of Measure" := 'ADET';
        Item.Modify(true);
    end;

    var
        Assert: Codeunit Assert;
}
