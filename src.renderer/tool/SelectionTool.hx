package tool;

class SelectionTool extends Tool< Array<GenericLevelElement> > {
	var selectionCursors : Array<ui.Cursor>;
	var moveStarted = false;
	var movePreview : h2d.Graphics;
	var isCopy = false;

	public function new() {
		super();

		movePreview = new h2d.Graphics();
		editor.levelRender.root.add(movePreview, Const.DP_UI);

		selectionCursors = [];
	}

	override function onDispose() {
		super.onDispose();
		movePreview.remove();
	}

	override function getDefaultValue():Array<GenericLevelElement> {
		return [];
	}

	override function getSelectionMemoryKey():Null<String> {
		return "selection";
	}

	function clearCursors() {
		for(c in selectionCursors)
			c.destroy();
		selectionCursors = [];
	}

	override function selectValue(v:Array<GenericLevelElement>) {
		super.selectValue(v);

		clearCursors();
		for(ge in getSelectedValue()) {
			var c = new ui.Cursor();
			selectionCursors.push(c);
			c.enablePermanentHighlights();
			c.set(switch ge {
				case IntGrid(li, cx, cy): GridCell(li, cx,cy);
				case Entity(li, ei): Entity(li, ei.def, ei, ei.x, ei.y);
				case Tile(li,cx,cy): Tiles(li, [li.getGridTile(cx,cy)], cx,cy);
				case PointField(li, ei, fi, arrayIdx):
					var pt = fi.getPointGrid(arrayIdx);
					GridCell(li, pt.cx, pt.cy);
			});
		}


		if( isSingle() ) {
			// Change layer
			switch v[0] {
				case IntGrid(li, _), Entity(li, _), Tile(li, _), PointField(li, _):
					if( li!=editor.curLayerInstance )
						editor.selectLayerInstance(li);
				case null:
			}

			// Selection effect
			switch v[0] {
				case IntGrid(li, cx, cy):
					var v = li.getIntGrid(cx,cy);
					editor.curTool.as(tool.lt.IntGridTool).selectValue(v);
					editor.levelRender.bleepRectPx( cx*li.def.gridSize, cy*li.def.gridSize, li.def.gridSize, li.def.gridSize, li.getIntGridColorAt(cx,cy) );

				case Entity(li, ei):
					editor.curTool.as(tool.lt.EntityTool).selectValue(ei.defUid); // BUG might crash
					editor.levelRender.bleepRectPx( ei.left, ei.top, ei.def.width, ei.def.height, ei.def.color );

				case Tile(li, cx, cy):
					var tid = li.getGridTile(cx,cy);

					var t = editor.curTool.as(tool.lt.TileTool);
					t.selectValue( { ids:[tid], mode:t.getMode() } ); // TODO re-support picking saved selections?

					editor.levelRender.bleepRectPx( cx*li.def.gridSize, cy*li.def.gridSize, li.def.gridSize, li.def.gridSize, 0xffcc00 );

				case PointField(li, ei, fi, arrayIdx):
					editor.curTool.as(tool.lt.EntityTool).selectValue(ei.defUid); // BUG might crash
					var pt = fi.getPointGrid(arrayIdx);
					if( pt!=null)
						editor.levelRender.bleepRectCase( pt.cx, pt.cy, 1, 1, ei.def.color );
			}

			editor.curTool.onValuePicking();

			// Open instance editor
			switch v[0] {
				case PointField(li, ei, fi, arrayIdx):
					ui.EntityInstanceEditor.openFor(ei);

				case Entity(li, instance):
					ui.EntityInstanceEditor.openFor(instance);

				case _:
			}
		}
	}

	override function updateCursor(m:MouseCoords) {
		super.updateCursor(m);

		for( c in selectionCursors )
			c.root.visible = !isRunning();

		// Default cursor
		if( isRunning() && rectangle ) {
			var r = Rect.fromMouseCoords(origin, m);
			editor.cursor.set( GridRect(curLayerInstance, r.left, r.top, r.wid, r.hei, 0xffffff) );
		}
		else if( isRunning() )
			editor.cursor.set(Moving);
		else if( isOveringSelection(m) )
			editor.cursor.set(Move);
		else if( !isRunning() ) {
			// Preview picking
			var ge = editor.getGenericLevelElementAt(m.levelX, m.levelY);
			switch ge {
			case null:
				editor.cursor.set(PickNothing);

			case IntGrid(li, cx, cy):
				var id = li.getIntGridIdentifierAt(cx,cy);
				editor.cursor.set(
					GridCell( li, cx, cy, li.getIntGridColorAt(cx,cy) ),
					id==null ? "#"+li.getIntGrid(cx,cy) : id
				);

			case Entity(li, ei):
				editor.cursor.set(
					Entity(li, ei.def, ei, ei.x, ei.y),
					ei.def.identifier,
					true
				);

			case Tile(li, cx,cy):
				editor.cursor.set(
					Tiles(li, [li.getGridTile(cx,cy)], cx, cy),
					"Tile "+li.getGridTile(cx,cy)
				);

			case PointField(li, ei, fi, arrayIdx):
				var pt = fi.getPointGrid(arrayIdx);
				editor.cursor.set( GridCell(li, pt.cx, pt.cy, ei.getSmartColor(false)) );
			}

			if( ge!=null )
				editor.cursor.setSystemCursor( hxd.Cursor.CustomCursor.getNativeCursor("grab") );
		}
	}

	public function isOveringSelection(m:MouseCoords) {
		if( isEmpty() )
			return false;

		for(ge in getSelectedValue()) {
			switch ge {
				case IntGrid(li, cx, cy):
					if( m.getLayerCx(li)==cx && m.getLayerCy(li)==cy )
						return true;

				case Entity(li, ei):
					if( ei.isOver(m.levelX,m.levelY) )
						return true;

				case Tile(li, cx, cy):
					if( m.getLayerCx(li)==cx && m.getLayerCy(li)==cy )
						return true;

				case PointField(li, ei, fi, arrayIdx):
					var pt = fi.getPointGrid(arrayIdx);
					if( pt!=null && m.getLayerCx(li)==pt.cx && m.getLayerCy(li)==pt.cy )
						return true;
			}
		}
		return false;
	}

	override function startUsing(m:MouseCoords, buttonId:Int) {
		isCopy = App.ME.isCtrlDown() && App.ME.isAltDown();
		moveStarted = false;
		editor.clearSpecialTool();
		movePreview.clear();

		super.startUsing(m, buttonId);

		if( buttonId==0 ) {
			if( rectangle )
				selectValue([]);
			else {
				var ge = editor.getGenericLevelElementAt(m.levelX, m.levelY);
				if( ge!=null )
					selectValue([ge]);
				else
					selectValue([]);
			}
		}
	}

	override function stopUsing(m:MouseCoords) {
		super.stopUsing(m);

		if( rectangle ) {
			var r = Rect.fromMouseCoords(origin, m);
			if( r.wid==1 && r.hei==1 ) {
				// Pick single value, in the end
				var ge = editor.getGenericLevelElementAt(m.levelX, m.levelY);
				if( ge!=null )
					selectValue([ge]);
				else
					selectValue([]);
			}
			else {
				// Pick every objects under rectangle
				var all = [];
				for(cy in r.top...r.bottom+1)
				for(cx in r.left...r.right+1) {
					var ge = editor.getGenericLevelElementAt(
						Std.int( (cx+0.5)*editor.curLayerDef.gridSize ),
						Std.int( (cy+0.5)*editor.curLayerDef.gridSize ),
						editor.levelRender.enhanceActiveLayer
					);
					if( ge!=null )
						all.push(ge);
				}

				selectValue(all);
			}
		}
		movePreview.clear();
	}

	public inline function get() return getSelectedValue();
	public function clear() {
		if( !isEmpty() )
			selectValue([]);
	}
	public inline function any() return getSelectedValue().length>0;
	public inline function isEmpty() return getSelectedValue().length==0;
	public inline function isSingle() return getSelectedValue().length==1;


	function duplicateSelection() : Null< Array<GenericLevelElement> > {
		switch getSelectedValue()[0] { // TODO support groups
			case IntGrid(li, cx, cy):
				return null;

			case Entity(li, instance):
				var ei = li.duplicateEntityInstance( instance );
				return [ GenericLevelElement.Entity(li, ei) ];

			case Tile(li, cx, cy):
				return null; // TODO support copy?

			case PointField(li, ei, fi, arrayIdx):
				return null; // TODO support copy?
		}
	}

	override function onMouseMove(m:MouseCoords) {
		super.onMouseMove(m);

		// Start moving elements only after a small elapsed mouse distance
		if( isRunning() && button==0 && !moveStarted && M.dist(origin.pageX, origin.pageY, m.pageX, m.pageY) >= 10*Const.SCALE ) {
			moveStarted = true;

			// Copy selection
			if( any() && isCopy ) {
				var copy = duplicateSelection();
				if( copy!=null )
					selectValue(copy);
			}
		}

		if( any() && isRunning() && moveStarted ) {
			switch getSelectedValue()[0] {
				case IntGrid(_), Tile(_):
					movePreview.clear();
					var fx = (origin.cx+0.5) * editor.curLayerDef.gridSize;
					var fy = (origin.cy+0.5) * editor.curLayerDef.gridSize;
					var tx = (m.cx+0.5) * editor.curLayerDef.gridSize;
					var ty = (m.cy+0.5) * editor.curLayerDef.gridSize;
					var a = Math.atan2(ty-fy, tx-fx);
					var arrow = 10;
					movePreview.lineStyle(1, 0xffffff, 1);
					movePreview.moveTo(fx,fy);
					movePreview.lineTo(tx,ty);

					movePreview.moveTo(tx,ty);
					movePreview.lineTo( tx + Math.cos(a+M.PI*0.8)*arrow, ty + Math.sin(a+M.PI*0.8)*arrow );

					movePreview.moveTo(tx,ty);
					movePreview.lineTo( tx + Math.cos(a-M.PI*0.8)*arrow, ty + Math.sin(a-M.PI*0.8)*arrow );

				case _:
			}

		}
	}


	public function getSelectedEntityInstance() : Null<led.inst.EntityInstance> {
		if( isEmpty() )
			return null;

		switch getSelectedValue()[0] {
			case null, IntGrid(_), Tile(_):
				return null;

			case PointField(li, ei, fi, arrayIdx):
				return ei;

			case Entity(curLayerInstance, instance):
				return instance;
		}
	}


	override function onHistorySaving() {
		super.onHistorySaving();

		var ei = getSelectedEntityInstance();
		if( ei!=null )
			editor.curLevelHistory.setLastStateBounds( ei.left, ei.top, ei.def.width, ei.def.height );
	}


	function moveSelection(m:MouseCoords, isOnStop:Bool) : Bool {
		var anyChange = false;

		for( ge in getSelectedValue() ) {
			switch ge {
				case Entity(li, ei):
					if( !isOnStop ) {
						var oldX = ei.x;
						var oldY = ei.y;
						ei.x = snapToGrid()
							? M.round( ( m.cx + ei.def.pivotX ) * curLayerInstance.def.gridSize )
							: m.levelX;
						ei.y = snapToGrid()
							? M.round( ( m.cy + ei.def.pivotY ) * curLayerInstance.def.gridSize )
							: m.levelY;
						var changed = oldX!=ei.x || oldY!=ei.y;
						if( changed )
							editor.ge.emit( EntityInstanceChanged(ei) );
						anyChange = anyChange || changed;
					}
					else
						selectValue([ Entity(curLayerInstance, ei) ]);

				case PointField(li, ei, fi, arrayIdx):
					if( !isOnStop ) {
						var old = fi.getPointStr(arrayIdx);
						fi.parseValue(arrayIdx, m.cx+Const.POINT_SEPARATOR+m.cy);

						var changed = old!=fi.getPointStr(arrayIdx);
						if( changed )
							editor.ge.emit( EntityInstanceChanged(ei) );
						anyChange = anyChange || changed;
					}
					else
						selectValue([ PointField(li,ei,fi,arrayIdx) ]);

				case IntGrid(li, cx,cy):
					if( isOnStop ) {
						editor.curLevelHistory.markChange(m.cx,m.cy);
						var v = li.getIntGrid(cx,cy);
						if( !isCopy )
							li.removeIntGrid(cx,cy);
						li.setIntGrid(m.cx, m.cy, v);
						editor.selectionTool.selectValue([ IntGrid(li, m.cx, m.cy) ]);
						anyChange = true;
					}

				case Tile(li,cx,cy):
					if( isOnStop ) {
						editor.curLevelHistory.markChange(m.cx,m.cy);
						var v = li.getGridTile(cx,cy);
						if( !isCopy )
							li.removeGridTile(cx,cy);
						li.setGridTile(m.cx, m.cy, v);
						editor.selectionTool.selectValue([ Tile(li, m.cx, m.cy) ]);
						anyChange = true;
					}
			}
		}
		return anyChange;
	}


	override function useAt(m:MouseCoords, isOnStop:Bool):Bool {
		if( any() && isRunning() && moveStarted )
			return moveSelection(m, isOnStop);
		else
			return super.useAt(m,isOnStop);
	}

	override function update() {
		super.update();
	}
}