local ItemDeck = require 'item_deck'
local TscFile  = require 'tsc_file'

local C = Class:extend()

local TSC_FILES = {}
do
  local ITEM_DATA = require 'database.items'
  for k, v in pairs(ITEM_DATA) do
    local filename = v.map .. '.tsc'
    if _.contains(TSC_FILES, filename) == false then
      table.insert(TSC_FILES, filename)
    end
  end
end

local WEAPONS_WHICH_CAN_NOT_BREAK_BLOCKS = {
  'wBubbline',
  'wFireball',
  'wSnake',
}

function C:randomize(path)
  resetLog()
  local success, dirStage = self:_mountDirectory(path)
  if not success then
    return "Could not find \"data\" subfolder.\n\nMaybe try dropping your Cave Story \"data\" folder in directly?"
  end
  self:_seedRngesus()
  local tscFiles = self:_createTscFiles(dirStage)
  -- self:_writePlaintext(tscFiles)
  local canNotBreakBlocks = self:_shuffleItems(tscFiles)
  self:_writeModifiedData(tscFiles)
  -- self:_writePlaintext(tscFiles)
  if canNotBreakBlocks then
    self:_copyModifiedFirstCave()
  end
  self:_writeLog()
  self:_unmountDirectory(path)
  return self:_getStatusMessage()
end

function C:_mountDirectory(path)
  local mountPath = 'mounted-data'
  assert(lf.mount(path, mountPath))
  local dirStage = '/' .. mountPath

  local items = lf.getDirectoryItems(dirStage)
  local containsData = _.contains(items, 'data')
  if containsData then
    dirStage = dirStage .. '/data'
  end

  -- For Cave Story+
  local items = lf.getDirectoryItems(dirStage)
  local containsBase = _.contains(items, 'base')
  if containsBase then
    dirStage = dirStage .. '/base'
  end

  local items = lf.getDirectoryItems(dirStage)
  local containsStage = _.contains(items, 'Stage')
  if containsStage then
    dirStage = dirStage .. '/Stage'
  else
    return false, ''
  end

  return true, dirStage
end

function C:_seedRngesus()
  local seed = tostring(os.time())
  math.randomseed(seed)
  logNotice(('Offering seed "%s" to RNGesus'):format(seed))
end

function C:_createTscFiles(dirStage)
  local tscFiles = {}
  for _, filename in ipairs(TSC_FILES) do
    local path = dirStage .. '/' .. filename
    tscFiles[filename] = TscFile(path)
  end
  return tscFiles
end

function C:_writePlaintext(tscFiles)
  local sourcePath = lf.getSourceBaseDirectory()

  -- Create /data/Plaintext if it doesn't already exist.
  local command = ('mkdir "%s"'):format(sourcePath .. '/data/Plaintext')
  os.execute(command) -- HERE BE DRAGONS!!!

  -- Write modified files.
  for filename, tscFile in pairs(tscFiles) do
    local path = sourcePath .. '/data/Plaintext/' .. filename
    tscFile:writePlaintextTo(path)
  end
end

function C:_shuffleItems(tscFiles)
  local itemDeck = ItemDeck()

  -- Place random weapon in either First Cave or Hermit Gunsmith.
  local firstArea, firstItemKey = unpack(_.sample({
    {'Cave.tsc', 'lFirstCave'},
    {'Pole.tsc', 'wPolarStar'},
  }))
  local firstWeapon = itemDeck:getWeapon()
  tscFiles[firstArea]:replaceSpecificItem(firstItemKey, firstWeapon)
  -- First cutscene won't play if missiles go in polar star chest.
  if firstArea == 'Cave.tsc' then
    tscFiles['Pole.tsc']:replaceSpecificItem('wPolarStar', itemDeck:getAnyExceptMissiles())
  end

  -- Replace all weapon trades with random weapons
  tscFiles['Curly.tsc']:replaceSpecificItem('wMachineGun', itemDeck:getWeapon())
  tscFiles['MazeA.tsc']:replaceSpecificItem('wSnake', itemDeck:getWeapon())
  tscFiles['Pole.tsc']:replaceSpecificItem('wSpur', itemDeck:getWeapon())
  tscFiles['Little.tsc']:replaceSpecificItem('wNemesis', itemDeck:getWeapon())

  -- Replace items which are part of elaborate events.
  -- Missiles jump to a global event, so shouldn't be used here.
  local items = {
    {'Santa.tsc', 'wFireball'},
    {'Chako.tsc', 'iChakosRouge'},
    {'MazeA.tsc', 'eTurbocharge'},
    {'MazeA.tsc', 'eWhimsicalStar'},
    {'Cent.tsc', 'lPlantationA'},
    {'Cent.tsc', 'iLifePot'},
  }
  for _, t in ipairs(items) do
    local file, itemKey = unpack(t)
    tscFiles[file]:replaceSpecificItem(itemKey, itemDeck:getAnyExceptMissiles())
  end

  -- Replace the rest of the items.
  for _, tscFile in pairs(tscFiles) do
    while tscFile:hasUnreplacedItems() do
      tscFile:replaceItem(itemDeck:getAny())
    end
  end

  return _.contains(WEAPONS_WHICH_CAN_NOT_BREAK_BLOCKS, firstWeapon.key)
end

function C:_writeModifiedData(tscFiles)
  local sourcePath = lf.getSourceBaseDirectory()

  -- Create /data/Stage if it doesn't already exist.
  local command = ('mkdir "%s"'):format(sourcePath .. '/data/Stage')
  os.execute(command) -- HERE BE DRAGONS!!!

  -- Write modified files.
  for filename, tscFile in pairs(tscFiles) do
    local path = sourcePath .. '/data/Stage/' .. filename
    tscFile:writeTo(path)
  end
end

function C:_copyModifiedFirstCave()
  local cavePxmPath = lf.getSourceBaseDirectory() .. '/data/Stage/Cave.pxm'
  local data = lf.read('database/Cave.pxm')
  assert(data)
  U.writeFile(cavePxmPath, data)
end

function C:_writeLog()
  local path = lf.getSourceBaseDirectory() .. '/data/log.txt'
  local data = getLogText()
  U.writeFile(path, data)
  print("\n")
end

function C:_unmountDirectory(path)
  assert(lf.unmount(path))
end

function C:_getStatusMessage()
  local warnings, errors = countLogWarningsAndErrors()
  local line1
  if warnings == 0 and errors == 0 then
    line1 = "Randomized data successfully created!"
  elseif warnings ~= 0 and errors == 0 then
    line1 = ("Randomized data was created with %d warning(s)."):format(warnings)
  else
    return ("Encountered %d error(s) and %d warning(s) when randomizing data!"):format(errors, warnings)
  end
  local line2 = "Next overwrite the files in your copy of Cave Story with the versions in the newly created \"data\" folder. Don't forget to save a backup of the originals!"
  local line3 = "Then play and have a fun!"
  local status = ("%s\n\n%s\n\n%s"):format(line1, line2, line3)
  return status
end

return C