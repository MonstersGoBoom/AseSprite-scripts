local byte = string.char
local binfile = nil
local map = {}
local images = { }
local colors = {}
local output_message = ""
local errors = 0
--
--	seperate platform from code 
--

function nswap(a)
	return (((a & 0xf) << 4) | ((a>>4)&0xf))
end

-- Mega 65 format 

local MEGA65 = {
	supportsPalette = 1
}
function MEGA65:ExportPal()
	for c = 0, #colors-1 do
		local color = colors:getColor(c)
		io.write(byte(nswap(color.red)))
	end
	for c = 0, #colors-1 do
		local color = colors:getColor(c)
		io.write(byte(nswap(color.green)))
	end
	for c = 0, #colors-1 do
		local color = colors:getColor(c)
		io.write(byte(nswap(color.blue)))
	end
end
function MEGA65:ExportTile(tile)
	for y=0,7 do 
		for xp = 0, 7 do 
			px = tile.pixels[1+((y*8) + xp)]	-- stupid off by 1
			io.write(byte(px))
		end
	end
end

function MEGA65:ExportMap(map,offset)
	for k,v in pairs(map) do 
		mindex = (v - 1) + offset
		io.write(byte(mindex&0xff))
		io.write(byte((mindex>>8)&0xff))
	end
end

-- C64 MC mode

local C64 = {
	luminance =  {0x0,0xf,0x3,0xb,0x5,0x9,0x1,0xd,0x6,0x2,0xa,0x4,0x8,0xe,0x7,0xc,0xff}
}

function C64:ExportMap(map,offset)
	for k,v in pairs(map) do 
		mindex = (v - 1) + offset
		io.write(byte(mindex))
	end
end

function C64:ExportTile(tile)
	if #tile.colors<=4 then
		
		--	sort the colors table by brightness 
		--	this seems to be quite nice
		table.sort(tile.colors, function(a, b) return C64.luminance[1+(a&0xf)] < C64.luminance[1+(b&0xf)] end)
		for y=0,7 do 
			--	clear the byte we write
			c = 0
			--	for the bits we scan every 2 pixels ( MC mode )
			--	we assume odd pixels are the same and don't care 
			for xp = 0, 7, 2 do 
				--	get the pixel from the tile data
				px = tile.pixels[1+((y*8) + xp)]
				--	double check for nil 
				if px==nil then
					px = 0
				end
				--	output color is an index between 0-#ncolors
				local oc = 0 
				--	check the colors array for this color to find it's index
				for ci = 1, #tile.colors do 
					if tile.colors[ci] == px then 
						oc = ci-1
						break
					end
				end
				--	output the color 0-3 into the byte for this line 
				c = c | ( oc << (6-xp))
			end
			--	write the byte out
			io.write(byte(c))
		end
	else
		--	kinda raster bar for chars with too many colors
		errors = errors + 1
		io.write(byte(0x00))
		io.write(byte(0x55))
		io.write(byte(0xaa))
		io.write(byte(0xff))
		io.write(byte(0xff))
		io.write(byte(0xaa))
		io.write(byte(0x55))
		io.write(byte(0x00))
	end
end

-- We create a string for each char for comparison later
-- note this is the raw 8bpp tile 

local function getTileData(img, x, y ,tw , th, mask)
	local res = {}
	res.pixels = {}
	res.colors = {}
	res.string = ""

	table.insert(res.colors,0)
	for  cy = 0, th-1 do
		for cx = 0, tw-1 do
				--	get the pixel 
				px = img:getPixel(cx+x, cy+y)
				-- store it in the string for comparison 
				res.string = res.string .. string.format("%02x",px)
				-- mask only the bottom 4 bits 
				px = px & mask
				--	check the colors for this tile 
				local found = -1
				for i,v in ipairs(res.colors) do
					if px==v then 
						found = i 
						break
					end
				end
				-- if we didn't find that color, insert it 
				if found==-1 then 
					table.insert(res.colors,px)
					found = #res.colors
				end
				-- insert the pixel itself 
				table.insert(res.pixels,px)
		end
	end

	-- check for repeated tiles
	for i,v in ipairs(images) do
    if res.string==v.string then 
      return i -- Return the existent tile index"
    end
  end
  -- we add it and return the index of it.
	table.insert(images, res)
	return #images
end

local function EncodeMap(input,tw,th,mask)
	local sprite = input.sprite
	local img = Image(sprite.spec)

	output_message = output_message .. " map " .. (img.width//8) .. " " .. (img.height//8)
	img:drawSprite(sprite, input)
	colors = sprite.palettes[1]
	-- collect the tiles this frame
	for y = 0, img.height-1, tw do
		for x = 0, img.width-1, th do
			local data = getTileData(img, x, y , tw, th,mask)
			table.insert(map,data)
		end
	end
end


local dlg = Dialog("Tilemizer")
dlg:file{ id="exportChars",
          label="Chars",
          title="C64 Char Export",
          open=false,
					save=true,
					filename="chars.bin",
          filetypes={"bin"}}

dlg:file{ id="exportMap",
          label="Map",
          title="C64 Map Export",
          open=false,
					save=true,
					filename="map.bin",
					filetypes={"bin"}}

dlg:file{ id="exportPal",
          label="Pal",
          title="Mega Map Export",
          open=false,
					save=true,
					filename="pal.bin",
					filetypes={"bin"}}

dlg:combobox{ id="TileFormat",
					label="TileFormat",
					option="C64",
					options={ "C64","MEGA65"} }
dlg:number{ id="OffsetTile",
					label="Offset#",
					text="0",
					decimals=0 }

dlg:button{ id="ok", text="OK" }
dlg:show()

local data = dlg.data
local System = nil
if data.ok then
	--	ok was pressed

	if data.TileFormat=="C64" then 
		System = C64
		EncodeMap(app.activeFrame,8,8,0xf)
	end
	if data.TileFormat=="MEGA65" then 
		System = MEGA65
		EncodeMap(app.activeFrame,8,8,0xff)
	end

	--	save colors
	if System.supportsPalette==1 then 
		binfile = io.open(data.exportPal, "wb")
		io.output(binfile)
		System:ExportPal()
		io.close(binfile)
	end

	--	tiles
	binfile = io.open(data.exportChars, "wb")
	io.output(binfile)
	for key,tile in pairs(images) do 
		System:ExportTile(tile)
	end 
	io.close(binfile)

	output_message = output_message .. " tiles " .. #images

	--	for now no metatiles
	-- map
	binfile = io.open(data.exportMap, "wb")
	io.output(binfile)
	System:ExportMap(map,data.OffsetTile)
	io.close(binfile)

	if errors~=0 then 
		output_message = output_message .. " Errors " .. errors
	end
	app.alert(output_message)
end

