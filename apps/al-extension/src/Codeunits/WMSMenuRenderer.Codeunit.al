codeunit 50029001 "WMS Menu Renderer"
{
    Access = Public;

    procedure GetMenuTree(MenuCode: Code[20]) JsonString: Text
    var
        Menu: Record "WMS Worker Menu";
        Item: Record "WMS Menu Item";
        Root: JsonObject;
        Items: JsonArray;
        Node: JsonObject;
    begin
        if not Menu.Get(MenuCode) then
            exit('{}');

        Root.Add('code', Menu.Code);
        Root.Add('description', Menu.Description);
        Root.Add('isRoot', Menu."Is Root");

        Item.SetRange("Menu Code", MenuCode);
        Item.SetCurrentKey("Menu Code", "Line No.");
        if Item.FindSet() then
            repeat
                Clear(Node);
                Node.Add('lineNumber', Item."Line No.");
                Node.Add('description', Item.Description);
                Node.Add('itemType', Format(Item."Item Type"));
                Node.Add('childMenuCode', Item."Child Menu Code");
                Node.Add('flowId', Item."Flow ID");
                Node.Add('icon', Item.Icon);
                Items.Add(Node);
            until Item.Next() = 0;

        Root.Add('items', Items);
        Root.WriteTo(JsonString);
    end;
}
