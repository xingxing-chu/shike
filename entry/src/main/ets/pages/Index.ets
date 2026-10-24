/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { abilityAccessCtrl, common, Permissions, Want } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { calendarManager } from '@kit.CalendarKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { fileIo } from '@kit.CoreFileKit'

// ============================= 常量 =============================
const APP_THEME_COLOR: string = '#007DFF'
const PAGE_BG: string = '#F1F3F5'
const TEXT_PRIMARY: string = '#182431'
const TEXT_SECONDARY: string = '#8A919F'
const CARD_DIVIDER_COLOR: string = '#F0F0F0'
const TRACK_BG: string = '#EEF1F4'
const CHIP_BG: string = '#E8F1FF'
const CHART_RANGE_LABELS: string[] = ['最近7天', '最近14天', '最近30天', '全部']
const EXPORT_RANGE_LABELS: string[] = ['全部时间', '最近7天', '最近30天', '自定义时间...']
const APPEARANCE_LABELS: string[] = ['白色', '黑色', '跟随系统']
const EXTRA_LEVEL_NAMES: string[] = ['三级标题', '四级标题', '五级标题', '六级标题', '七级标题', '八级标题']
const FONT_SIZE_LABELS: string[] = ['小', '标准', '大', '特大']
const FONT_SIZE_SCALES: number[] = [0.85, 1, 1.15, 1.3]
const FONT_FAMILY_LABELS: string[] = ['默认', '衬线', '等宽']
const FONT_FAMILY_VALUES: string[] = ['HarmonyOS Sans', 'serif', 'monospace']

// ============================= 工具函数 =============================
function pad2(n: number): string {
  if (n < 10) {
    return `0${n}`
  }
  return `${n}`
}

function formatShort(ts: number): string {
  const d = new Date(ts)
  return `${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ${pad2(d.getHours())}:${pad2(d.getMinutes())}`
}

function formatFull(ts: number): string {
  const d = new Date(ts)
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ${pad2(d.getHours())}:${pad2(d.getMinutes())}`
}

function isSameDay(a: number, b: number): boolean {
  const da = new Date(a)
  const db = new Date(b)
  return da.getFullYear() === db.getFullYear() && da.getMonth() === db.getMonth() && da.getDate() === db.getDate()
}

function dayLabelOf(ts: number): string {
  if (isSameDay(ts, Date.now())) {
    return '今天'
  }
  if (isSameDay(ts, Date.now() - 86400000)) {
    return '昨天'
  }
  const d = new Date(ts)
  return `${d.getMonth() + 1}月${d.getDate()}日`
}

function startOfDay(ts: number): number {
  const d = new Date(ts)
  d.setHours(0, 0, 0, 0)
  return d.getTime()
}

function endOfDay(ts: number): number {
  const d = new Date(ts)
  d.setHours(23, 59, 59, 999)
  return d.getTime()
}

function startOfWeek(): number {
  const d = new Date()
  const offset = (d.getDay() + 6) % 7
  d.setDate(d.getDate() - offset)
  d.setHours(0, 0, 0, 0)
  return d.getTime()
}

function combineDateTime(datePart: Date, timePart: Date): number {
  const combined = new Date(datePart.getFullYear(), datePart.getMonth(), datePart.getDate(),
    timePart.getHours(), timePart.getMinutes(), 0)
  return combined.getTime()
}

function distinctDayCount(records: RecordItem[]): number {
  const marks: string[] = []
  records.forEach((rec: RecordItem) => {
    const d = new Date(rec.recordTime)
    const mark = `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`
    if (marks.indexOf(mark) < 0) {
      marks.push(mark)
    }
  })
  return marks.length
}

function distinctValues(values: string[]): string[] {
  const result: string[] = []
  values.forEach((v: string) => {
    if (v !== '' && result.indexOf(v) < 0) {
      result.push(v)
    }
  })
  return result
}

// 全局字体大小缩放（由设置页控制，通过 AppStorage 'fontSizeIndex' 共享）
function fs(base: number): number {
  const idx = AppStorage.get<number>('fontSizeIndex')
  let scale = 1
  if (idx !== undefined && idx >= 0 && idx < FONT_SIZE_SCALES.length) {
    scale = FONT_SIZE_SCALES[idx]
  }
  return Math.round(base * scale * 10) / 10
}

// 全局字体族（由设置页控制，通过 AppStorage 'fontFamilyIndex' 共享）
function ff(): string {
  const idx = AppStorage.get<number>('fontFamilyIndex')
  if (idx !== undefined && idx >= 0 && idx < FONT_FAMILY_VALUES.length) {
    return FONT_FAMILY_VALUES[idx]
  }
  return FONT_FAMILY_VALUES[0]
}

function countByTitle(records: RecordItem[]): TitleCount[] {
  const result: TitleCount[] = []
  records.forEach((rec: RecordItem) => {
    const amount = Number(rec.amount)
    const safeAmount = Number.isNaN(amount) ? 0 : amount
    const found = result.find((item: TitleCount): boolean => item.name === rec.title)
    if (found !== undefined) {
      found.count += 1
      found.amountTotal += safeAmount
      if (found.unit === '' && rec.unit !== '') {
        found.unit = rec.unit
      }
    } else {
      result.push(new TitleCount(rec.title, 1, safeAmount, rec.unit))
    }
  })
  result.sort((a: TitleCount, b: TitleCount): number => b.count - a.count)
  return result
}

// 次数 + 数值/单位汇总，如：8 次 · 2000ml
function titleStatText(item: TitleCount): string {
  const total = Math.round(item.amountTotal * 100) / 100
  if (total > 0 && item.unit !== '') {
    return `${item.count} 次 · ${total.toString()}${item.unit}`
  }
  if (total > 0) {
    return `${item.count} 次 · ${total.toString()}`
  }
  return `${item.count} 次`
}

// ============================= 数据模型 =============================
class RecordItem {
  id: number
  title: string
  subTitle: string
  content: string
  note: string
  tags: string[]
  recordTime: number
  remindAt: number
  amount: string
  unit: string

  constructor(id: number, title: string, subTitle: string, content: string, note: string,
    tags: string[], recordTime: number, remindAt: number, amount: string, unit: string) {
    this.id = id
    this.title = title
    this.subTitle = subTitle
    this.content = content
    this.note = note
    this.tags = tags
    this.recordTime = recordTime
    this.remindAt = remindAt
    this.amount = amount
    this.unit = unit
  }
}

class LevelInput {
  levelName: string
  levelValue: string

  constructor(levelName: string) {
    this.levelName = levelName
    this.levelValue = ''
  }
}

class TemplateItem {
  id: number
  name: string
  subTitle: string
  icon: string
  usageCount: number
  amount: string
  unit: string
  content: string
  note: string
  extraLevels: LevelInput[]

  constructor(id: number, name: string, subTitle: string, icon: string, usageCount: number,
    amount: string, unit: string, content: string, note: string, extraLevels: LevelInput[]) {
    this.id = id
    this.name = name
    this.subTitle = subTitle
    this.icon = icon
    this.usageCount = usageCount
    this.amount = amount
    this.unit = unit
    this.content = content
    this.note = note
    this.extraLevels = extraLevels
  }
}

class TitleCount {
  name: string
  count: number
  amountTotal: number
  unit: string

  constructor(name: string, count: number, amountTotal: number, unit: string) {
    this.name = name
    this.count = count
    this.amountTotal = amountTotal
    this.unit = unit
  }
}

class TimelineEntry {
  entryKey: string
  isHeader: boolean
  headerLabel: string
  record: RecordItem | null

  constructor(entryKey: string, isHeader: boolean, headerLabel: string, record: RecordItem | null) {
    this.entryKey = entryKey
    this.isHeader = isHeader
    this.headerLabel = headerLabel
    this.record = record
  }
}

let recordIdSeed: number = 500

function nextRecordId(): number {
  recordIdSeed += 1
  return recordIdSeed
}

let templateIdSeed: number = 500

function nextTemplateId(): number {
  templateIdSeed += 1
  return templateIdSeed
}

// ============================= 通用卡片样式 =============================
@Styles
function cardLook() {
  .padding(16)
  .borderRadius(16)
  .backgroundColor(Color.White)
  .shadow({ radius: 12, color: '#12000000', offsetX: 0, offsetY: 4 })
}

// ============================= 通用小组件 =============================
@Component
struct SummaryCell {
  @StorageLink('fontSizeIndex') fontSizeIndex: number = 1
  @Prop statCount: number = 0
  cellLabel: string = ''
  cellKind: string = ''
  onCellClick: (kind: string) => void = (kind: string) => {
  }

  build() {
    Column({ space: 4 }) {
      Text(this.statCount.toString())
        .fontSize(fs(22)).fontFamily(ff())
        .fontWeight(FontWeight.Bold)
        .fontColor(APP_THEME_COLOR)
      Text(this.cellLabel)
        .fontSize(fs(12)).fontFamily(ff())
        .fontColor(TEXT_SECONDARY)
    }
    .layoutWeight(1)
    .padding({ top: 12, bottom: 12 })
    .onClick(() => {
      this.onCellClick(this.cellKind)
    })
  }
}

@Component
struct OverviewCell {
  @StorageLink('fontSizeIndex') fontSizeIndex: number = 1
  @Prop cellValue: string = '0'
  cellLabel: string = ''

  build() {
    Column({ space: 4 }) {
      Text(this.cellValue)
        .fontSize(fs(20)).fontFamily(ff())
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_PRIMARY)
      Text(this.cellLabel)
        .fontSize(fs(12)).fontFamily(ff())
        .fontColor(TEXT_SECONDARY)
    }
    .layoutWeight(1)
  }
}

@Component
struct RecordCard {
  @StorageLink('fontSizeIndex') fontSizeIndex: number = 1
  @Prop rec: RecordItem = new RecordItem(0, '暂无记录', '', '点击右下角 + 开始第一条记录', '', [], Date.now(), 0, '', '')

  amountText(): string {
    if (this.rec.amount === '') {
      return ''
    }
    if (this.rec.unit === '') {
      return `数值：${this.rec.amount}`
    }
    return `数值：${this.rec.amount} ${this.rec.unit}`
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Text(this.rec.title)
          .fontSize(fs(16)).fontFamily(ff())
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 180 })
        if (this.rec.subTitle !== '') {
          Text(this.rec.subTitle)
            .fontSize(fs(13)).fontFamily(ff())
            .fontColor(APP_THEME_COLOR)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 120 })
        }
        Blank()
        Text(formatShort(this.rec.recordTime))
          .fontSize(fs(12)).fontFamily(ff())
          .fontColor(TEXT_SECONDARY)
      }
      .width('100%')

      if (this.rec.content !== '') {
        Text(this.rec.content)
          .fontSize(fs(14)).fontFamily(ff())
          .fontColor(TEXT_SECONDARY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      if (this.amountText() !== '') {
        Text(this.amountText())
          .fontSize(fs(12)).fontFamily(ff())
          .fontColor(TEXT_SECONDARY)
          .width('100%')
      }
      if (this.rec.note !== '') {
        Text(`备注：${this.rec.note}`)
          .fontSize(fs(12)).fontFamily(ff())
          .fontColor(TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      if (this.rec.tags.length > 0) {
        Row({ space: 8 }) {
          ForEach(this.rec.tags, (tag: string) => {
            Text(tag)
              .fontSize(fs(11)).fontFamily(ff())
              .fontColor(APP_THEME_COLOR)
              .backgroundColor(CHIP_BG)
              .borderRadius(8)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          }, (tag: string) => tag)
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .cardLook()
  }
}

// 纯 Row/Column 组合的柱状图：柱顶显示次数、柱底显示标题，按次数降序
@Component
struct BarChartView {
  @StorageLink('fontSizeIndex') fontSizeIndex: number = 1
  @Prop dataItems: TitleCount[] = []

  build() {
    Row({ space: 14 }) {
      ForEach(this.dataItems, (item: TitleCount) => {
        Column({ space: 4 }) {
          Text(item.count.toString())
            .fontSize(fs(12)).fontFamily(ff())
            .fontWeight(FontWeight.Medium)
            .fontColor(TEXT_PRIMARY)
          Column()
            .width(24)
            .height(this.getBarHeight(item.count))
            .backgroundColor(APP_THEME_COLOR)
            .borderRadius({ topLeft: 4, topRight: 4 })
          Text(item.name)
            .fontSize(fs(11)).fontFamily(ff())
            .fontColor(TEXT_SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 56 })
        }
      }, (item: TitleCount) => `${item.name}_${item.count.toString()}`)
    }
    .alignItems(VerticalAlign.Bottom)
  }

  getMaxCount(): number {
    let maxCount = 0
    this.dataItems.forEach((item: TitleCount) => {
      if (item.count > maxCount) {
        maxCount = item.count
      }
    })
    return maxCount
  }

  getBarHeight(count: number): number {
    const maxCount = this.getMaxCount()
    if (maxCount <= 0) {
      return 6
    }
    return Math.max(6, Math.round(count / maxCount * 100))
  }
}

// ============================= 首页 Tab =============================
@Component
struct HomeTab {
  @StorageLink('fontSizeIndex') fontSizeIndex: number = 1
  onOpenSheet: () => void = () => {
  }
  onOpenDetail: (kind: string) => void = (kind: string) => {
  }
  @StorageLink('allRecords') recordList: RecordItem[] = []
  @State chartRangeIndex: number = 0

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Scroll() {
        Column({ space: 12 }) {
          // 最近记录
          Column() {
            Text('最近记录')
              .fontSize(fs(16)).fontFamily(ff())
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT_PRIMARY)
              .width('100%')
            RecordCard({ rec: this.getLatestRecord() })
              .margin({ top: 10 })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          // 今日 / 本周摘要
          Column() {
            Text('今日 / 本周摘要')
              .fontSize(fs(16)).fontFamily(ff())
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT_PRIMARY)
              .width('100%')
            Row() {
              SummaryCell({
                statCount: this.getTodayCount(),
                cellLabel: '今日记录',
                cellKind: 'today',
                onCellClick: (kind: string) => {
                  this.onOpenDetail(kind)
                }
              })
              Divider()
                .vertical(true)
                .height(32)
              SummaryCell({
                statCount: this.getWeekCount(),
                cellLabel: '本周记录',
                cellKind: 'week',
                onCellClick: (kind: string) => {
                  this.onOpenDetail(kind)
                }
              })
              Divider()
                .vertical(true)
                .height(32)
              SummaryCell({
                statCount: this.getRemindRecords().length,
                cellLabel: '待提醒',
                cellKind: 'remind',
                onCellClick: (kind: string) => {
                  this.onOpenDetail(kind)
                }
              })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: 4 })
          }
          .width('100%')

          // 高频事项 Top 3
          Column() {
            Text('高频事项 Top 3')
              .fontSize(fs(16)).fontFamily(ff())
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT_PRIMARY)
              .width('100%')
            Column({ space: 10 }) {
              if (this.getTopItems().length === 0) {
                Text('暂无记录数据，点击右下角 + 开始记录')
                  .fontSize(fs(13)).fontFamily(ff())
                  .fontColor(TEXT_SECONDARY)
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding({ top: 4, bottom: 4 })
              }
              ForEach(this.getTopItems(), (item: TitleCount, index: number) => {
                Row({ space: 10 }) {
                  Text((index + 1).toString())
                    .width(20)
                    .height(20)
                    .fontSize(fs(12)).fontFamily(ff())
                    .textAlign(TextAlign.Center)
                    .fontColor(Color.White)
                    .backgroundColor(APP_THEME_COLOR)
                    .borderRadius(10)
                  Text(item.name)
                    .fontSize(fs(14)).fontFamily(ff())
                    .fontColor(TEXT_PRIMARY)
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(titleStatText(item))
                    .fontSize(fs(13)).fontFamily(ff())
                    .fontColor(TEXT_SECONDARY)
                }
                .width('100%')
              }, (item: TitleCount) => `${item.name}_${item.count.toString()}`)
            }
            .width('100%')
            .margin({ top: 12 })
          }
          .width('100%')

          // 精简统计图表
          Column() {
            Row() {
              Text('精简统计')
                .fontSize(fs(16)).fontFamily(ff())
                .fontWeight(FontWeight.Bold)
                .fontColor(TEXT_PRIMARY)
              Blank()
              Select(this.getChartRangeOptions())
                .selected(this.chartRangeIndex)
                .value(this.getChartRangeLabel())
                .font({ size: 13 })
                .fontColor(TEXT_PRIMARY)
                .constraintSize({ maxWidth: 132 })
                .onSelect((index: number) => {
                  this.chartRangeIndex = index
                })
            }
            .width('100%')

            if (this.getChartItems().length === 0) {
              Text('暂无统计数据')
                .fontSize(fs(13)).fontFamily(ff())
                .fontColor(TEXT_SECONDARY)
                .width('100%')
                .textAlign(TextAlign.Center)
                .margin({ top: 20, bottom: 12 })
            } else {
              Row() {
                BarChartView({ dataItems: this.getChartItems() })
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .margin({ top: 16 })
            }
          }
          .width('100%')

          // 待提醒列表
          Column() {
            Text('待提醒')
              .fontSize(fs(16)).fontFamily(ff())
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT_PRIMARY)
              .width('100%')
            if (this.getRemindRecords().length === 0) {
              Text('暂无待提醒事项')
                .fontSize(fs(13)).fontFamily(ff())
                .fontColor(TEXT_SECONDARY)
                .width('100%')
                .textAlign(TextAlign.Center)
                .margin({ top: 12 })
            } else {
              Column({ space: 12 }) {
                ForEach(this.getRemindRecords(), (rec: RecordItem) => {
                  Row({ space: 10 }) {
                    Text('🔔')
                      .fontSize(fs(18)).fontFamily(ff())
                    Column({ space: 2 }) {
                      Text(this.getRemindTitle(rec))
                        .fontSize(fs(14)).fontFamily(ff())
                        .fontColor(TEXT_PRIMARY)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(formatFull(rec.remindAt))
                        .fontSize(fs(12)).fontFamily(ff())
                        .fontColor(TEXT_SECONDARY)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                  }
                  .width('100%')
                }, (rec: RecordItem) => `remind_${rec.id.toString()}_${rec.remindAt.toString()}`)
              }
              .width('100%')
              .margin({ top: 12 })
            }
          }
          .width('100%')
        }
        .padding({ left: 16, right: 16, top: 12, bottom: 96 })
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)

      // 右下角悬浮加号（60x60 蓝色圆形，仅首页显示）
      Button('+', { type: ButtonType.Circle, stateEffect: true })
        .width(60)
        .height(60)
        .fontSize(fs(30)).fontFamily(ff())
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .backgroundColor(APP_THEME_COLOR)
        .shadow({ radius: 16, color: '#33007DFF', offsetX: 0, offsetY: 6 })
        .margin({ right: 20, bottom: 24 })
        .onClick(() => {
          this.onOpenSheet()
        })
    }
    .width('100%')
    .height('100%')
  }

  getLatestRecord(): RecordItem {
    const sorted: RecordItem[] = this.recordList.slice()
      .sort((a: RecordItem, b: RecordItem): number => b.recordTime - a.recordTime)
    if (sorted.length > 0) {
      return sorted[0]
    }
    return new RecordItem(0, '暂无记录', '', '点击右下角 + 开始第一条记录', '', [], Date.now(), 0, '', '')
  }

  getTodayCount(): number {
    return this.recordList.filter((rec: RecordItem): boolean => rec.recordTime >= startOfDay(Date.now())).length
  }

  getWeekCount(): number {
    return this.recordList.filter((rec: RecordItem): boolean => rec.recordTime >= startOfWeek()).length
  }

  getRemindRecords(): RecordItem[] {
    return this.recordList.filter((rec: RecordItem): boolean => rec.remindAt > Date.now())
      .sort((a: RecordItem, b: RecordItem): number => a.remindAt - b.remindAt)
  }

  getRemindTitle(rec: RecordItem): string {
    if (rec.subTitle !== '') {
      return `${rec.title} · ${rec.subTitle}`
    }
    return rec.title
  }

  getTopItems(): TitleCount[] {
    return countByTitle(this.recordList).slice(0, 3)
  }

  getChartRangeOptions(): SelectOption[] {
    return CHART_RANGE_LABELS.map((label: string): SelectOption => {
      return { value: label }
    })
  }

  getChartRangeLabel(): string {
    return CHART_RANGE_LABELS[this.chartRangeIndex]
  }

  getChartItems(): TitleCount[] {
    const rangeDays: number[] = [7, 14, 30, 3650]
    const days = rangeDays[this.chartRangeIndex]
    const since = Date.now() - days * 86400000
    const filtered: RecordItem[] =
      this.recordList.filter((rec: RecordItem): boolean => rec.recordTime >= since)
    return countByTitle(filtered).slice(0, 6)
  }
}

// ============================= 时间线 Tab =============================
@Component
struct TimelineTab {
  @StorageLink('fontSizeIndex') fontSizeIndex: number = 1
  @StorageLink('allRecords') recordList: RecordItem[] = []
  @State keyword: string = ''

  build() {
    Column() {
      Search({ placeholder: '搜索标题、内容', value: this.keyword })
        .height(40)
        .backgroundColor(Color.White)
        .margin({ left: 16, right: 16, top: 12 })
        .onChange((value: string) => {
          this.keyword = value
        })

      if (this.getTimelineEntries().length === 0) {
        Column() {
          if (this.keyword.trim() === '') {
            Text('暂无记录，去首页点击 + 添加吧')
              .fontSize(fs(14)).fontFamily(ff())
              .fontColor(TEXT_SECONDARY)
              .textAlign(TextAlign.Center)
          } else {
            Text('没有找到相关记录')
              .fontSize(fs(14)).fontFamily(ff())
              .fontColor(TEXT_SECONDARY)
              .textAlign(TextAlign.Center)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Start)
        .padding({ top: 64 })
      } else {
        List({ space: 10 }) {
          ForEach(this.getTimelineEntries(), (entry: TimelineEntry) => {
            if (entry.isHeader) {
              ListItem() {
                Text(entry.headerLabel)
                  .fontSize(fs(14)).fontFamily(ff())
                  .fontWeight(FontWeight.Medium)
                  .fontColor(TEXT_SECONDARY)
                  .width('100%')
                  .margin({ top: 8 })
              }
            } else {
              ListItem() {
                RecordCard({ rec: this.entryRecord(entry) })
              }
              .swipeAction({
                start: {
                  builder: (): void => {
                    this.deleteSwipeBuilder(entry)
                  },
                  onAction: () => {
                    this.deleteRecord(this.entryRecord(entry).id)
                  }
                },
                edgeEffect: SwipeEdgeEffect.Spring
              })
            }
          }, (entry: TimelineEntry) => entry.entryKey)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .padding({ left: 16, right: 16, top: 8, bottom: 24 })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  deleteSwipeBuilder(entry: TimelineEntry) {
    Column({ space: 4 }) {
      Text('🗑️')
        .fontSize(fs(18)).fontFamily(ff())
      Text('删除')
        .fontSize(fs(11)).fontFamily(ff())
        .fontColor(Color.White)
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#E8402F')
    .borderRadius(12)
    .onClick(() => {
      this.deleteRecord(this.entryRecord(entry).id)
    })
  }

  deleteRecord(id: number): void {
    const updated: RecordItem[] =
      this.recordList.filter((rec: RecordItem): boolean => rec.id !== id)
    this.recordList = updated
    this.showToast('记录已删除')
  }

  showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  entryRecord(entry: TimelineEntry): RecordItem {
    return entry.record ?? new RecordItem(0, '已删除', '', '', '', [], Date.now(), 0, '', '')
  }

  getTimelineEntries(): TimelineEntry[] {
    const kw = this.keyword.trim().toLowerCase()
    const sorted: RecordItem[] = this.recordList.slice()
      .sort((a: RecordItem, b: RecordItem): number => b.recordTime - a.recordTime)
    const filtered: RecordItem[] = kw === '' ? sorted : sorted.filter((rec: RecordItem): boolean => {
      return rec.title.toLowerCase().indexOf(kw) >= 0 || rec.subTitle.toLowerCase().indexOf(kw) >= 0 ||
        rec.content.toLowerCase().indexOf(kw) >= 0
    })
    const entries: TimelineEntry[] = []
    let lastLabel = ''
    filtered.forEach((rec: RecordItem) => {
      const label = dayLabelOf(rec.recordTime)
      if (label !== lastLabel) {
        entries.push(new TimelineEntry(`header_${label}`, true, label, null))
        lastLabel = label
      }
      entries.push(new TimelineEntry(`record_${rec.id.toString()}`, false, '', rec))
    })
    return entries
  }
}

// ============================= 统计 Tab =============================
@Component
struct StatsTab {
  @StorageLink('fontSizeIndex') fontSizeIndex: number = 1
  @StorageLink('allRecords') recordList: RecordItem[] = []
  @StorageLink('allTemplates') templateList: TemplateItem[] = []

  build() {
    Scroll() {
      Column({ space: 12 }) {
        // 数据总览
        Column() {
          Text('数据总览')
            .fontSize(fs(16)).fontFamily(ff())
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_PRIMARY)
            .width('100%')
          Row() {
            OverviewCell({ cellValue: this.recordList.length.toString(), cellLabel: '总记录' })
            OverviewCell({ cellValue: this.getWeekCount().toString(), cellLabel: '本周新增' })
            OverviewCell({ cellValue: distinctDayCount(this.recordList).toString(), cellLabel: '记录天数' })
            OverviewCell({ cellValue: this.templateList.length.toString(), cellLabel: '模板数' })
          }
          .width('100%')
          .margin({ top: 14 })
        }
        .width('100%')

        // 高频事项回顾
        Column() {
          Text('高频事项回顾')
            .fontSize(fs(16)).fontFamily(ff())
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_PRIMARY)
            .width('100%')
          Column({ space: 12 }) {
            if (this.getAllItems().length === 0) {
              Text('暂无记录数据')
                .fontSize(fs(13)).fontFamily(ff())
                .fontColor(TEXT_SECONDARY)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 4, bottom: 4 })
            }
            ForEach(this.getAllItems(), (item: TitleCount, index: number) => {
              Column({ space: 6 }) {
                Row() {
                  Text(`${index + 1}. ${item.name}`)
                    .fontSize(fs(14)).fontFamily(ff())
                    .fontColor(TEXT_PRIMARY)
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(titleStatText(item))
                    .fontSize(fs(13)).fontFamily(ff())
                    .fontColor(TEXT_SECONDARY)
                }
                .width('100%')
                Row() {
                  Column()
                    .width(this.getPercentOf(item))
                    .height(6)
                    .backgroundColor(APP_THEME_COLOR)
                    .borderRadius(3)
                }
                .width('100%')
                .height(6)
                .backgroundColor(TRACK_BG)
                .borderRadius(3)
              }
              .width('100%')
            }, (item: TitleCount) => `${item.name}_${item.count.toString()}`)
          }
          .width('100%')
          .margin({ top: 12 })
        }
        .width('100%')

        // 记录趋势 Top 10（支持横向滑动）
        Column() {
          Text('记录趋势 (Top 10)')
            .fontSize(fs(16)).fontFamily(ff())
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_PRIMARY)
            .width('100%')
          if (this.getTrendItems().length === 0) {
            Text('暂无统计数据')
              .fontSize(fs(13)).fontFamily(ff())
              .fontColor(TEXT_SECONDARY)
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ top: 12 })
          } else {
            Scroll() {
              Row() {
                BarChartView({ dataItems: this.getTrendItems() })
              }
              .padding({ top: 16, bottom: 4 })
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
            .margin({ top: 4 })
          }
        }
        .width('100%')

        // 分类占比
        Column() {
          Text('分类占比')
            .fontSize(fs(16)).fontFamily(ff())
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_PRIMARY)
            .width('100%')
          Column({ space: 12 }) {
            if (this.getAllItems().length === 0) {
              Text('暂无记录数据')
                .fontSize(fs(13)).fontFamily(ff())
                .fontColor(TEXT_SECONDARY)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 4, bottom: 4 })
            }
            ForEach(this.getAllItems(), (item: TitleCount) => {
              Row({ space: 10 }) {
                Text(item.name)
                  .fontSize(fs(14)).fontFamily(ff())
                  .fontColor(TEXT_PRIMARY)
                  .width(76)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Row() {
                  Column()
                    .width(this.getPercentOf(item))
                    .height(6)
                    .backgroundColor(APP_THEME_COLOR)
                    .borderRadius(3)
                }
                .layoutWeight(1)
                .height(6)
                .backgroundColor(TRACK_BG)
                .borderRadius(3)
                Text(this.getPercentOf(item))
                  .fontSize(fs(12)).fontFamily(ff())
                  .fontColor(TEXT_SECONDARY)
                  .width(44)
                  .textAlign(TextAlign.End)
              }
              .width('100%')
            }, (item: TitleCount) => `${item.name}_${this.getPercentOf(item)}`)
          }
          .width('100%')
          .margin({ top: 12 })
        }
        .width('100%')
      }
      .padding({ left: 16, right: 16, top: 12, bottom: 24 })
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }

  getWeekCount(): number {
    return this.recordList.filter((rec: RecordItem): boolean => rec.recordTime >= startOfWeek()).length
  }

  getAllItems(): TitleCount[] {
    return countByTitle(this.recordList)
  }

  getTrendItems(): TitleCount[] {
    return countByTitle(this.recordList).slice(0, 10)
  }

  getPercentOf(item: TitleCount): string {
    const total = this.recordList.length
    if (total <= 0) {
      return '0%'
    }
    return `${Math.round(item.count / total * 100).toString()}%`
  }
}

// ============================= 个人信息编辑组件 =============================
@Component
struct ProfileEditor {
  @StorageLink('fontSizeIndex') fontSizeIndex: number = 1
  @StorageLink('userName') userName: string = ''
  @StorageLink('userAvatar') userAvatar: string = ''
  @State inputName: string = ''
  onSaved: () => void = () => {
  }

  aboutToAppear(): void {
    this.inputName = this.userName
  }

  build() {
    Column({ space: 16 }) {
      // 头像
      Column() {
        if (this.userAvatar !== '') {
          Image(this.userAvatar)
            .width(88)
            .height(88)
            .borderRadius(44)
            .objectFit(ImageFit.Cover)
        } else {
          Column({ space: 4 }) {
            Text('👤')
              .fontSize(fs(36)).fontFamily(ff())
            Text('点击选择头像')
              .fontSize(fs(11)).fontFamily(ff())
              .fontColor(TEXT_SECONDARY)
          }
          .justifyContent(FlexAlign.Center)
        }
      }
      .width(88)
      .height(88)
      .borderRadius(44)
      .backgroundColor(CHIP_BG)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.pickAvatar()
      })

      // 昵称
      Column({ space: 8 }) {
        Text('昵称')
          .fontSize(fs(14)).fontFamily(ff())
          .fontColor(TEXT_SECONDARY)
          .width('100%')
        TextInput({ placeholder: '请输入昵称', text: this.inputName })
          .height(44)
          .width('100%')
          .onChange((value: string) => {
            this.inputName = value
          })
      }
      .width('100%')

      Button('保存')
        .width('100%')
        .height(44)
        .fontSize(fs(16)).fontFamily(ff())
        .backgroundColor(APP_THEME_COLOR)
        .fontColor(Color.White)
        .margin({ top: 4 })
        .onClick(() => {
          this.save()
        })
    }
    .width('100%')
    .padding({ top: 8, bottom: 24 })
  }

  async pickAvatar(): Promise<void> {
    try {
      const selectOptions = new photoAccessHelper.PhotoSelectOptions()
      selectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
      selectOptions.maxSelectNumber = 1
      const photoPicker = new photoAccessHelper.PhotoViewPicker()
      const selectResult: photoAccessHelper.PhotoSelectResult = await photoPicker.select(selectOptions)
      if (selectResult.photoUris.length === 0) {
        return
      }
      const context = getContext(this)
      const srcFile = fileIo.openSync(selectResult.photoUris[0], fileIo.OpenMode.READ_ONLY)
      const fileSize = fileIo.statSync(srcFile.fd).size
      const buffer = new ArrayBuffer(fileSize)
      fileIo.readSync(srcFile.fd, buffer)
      fileIo.closeSync(srcFile)
      const destPath = `${context.filesDir}/user_avatar`
      const destFile = fileIo.openSync(destPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      fileIo.writeSync(destFile.fd, buffer)
      fileIo.closeSync(destFile)
      this.userAvatar = `file://${destPath}`
    } catch (error) {
      this.showToast('选择头像失败')
    }
  }

  save(): void {
    const name = this.inputName.trim()
    if (name === '') {
      this.showToast('请输入昵称')
      return
    }
    this.userName = name
    this.showToast('保存成功')
    this.onSaved()
  }

  showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }
}

// ============================= 我的 Tab =============================
@Component
struct MineTab {
  @StorageLink('fontSizeIndex') fontSizeIndex: number = 1
  pathStack: NavPathStack = new NavPathStack()
  @StorageLink('allRecords') recordList: RecordItem[] = []
  @StorageLink('userName') userName: string = ''
  @StorageLink('userAvatar') userAvatar: string = ''
  @State isShowProfileSheet: boolean = false

  build() {
    Scroll() {
      Column({ space: 12 }) {
        // 用户信息卡片
        Row({ space: 14 }) {
          if (this.userAvatar !== '') {
            Image(this.userAvatar)
              .width(60)
              .height(60)
              .borderRadius(30)
              .objectFit(ImageFit.Cover)
          } else {
            Column() {
              Text('👤')
                .fontSize(fs(28)).fontFamily(ff())
            }
            .width(60)
            .height(60)
            .borderRadius(30)
            .backgroundColor(CHIP_BG)
            .justifyContent(FlexAlign.Center)
          }

          Column({ space: 4 }) {
            Text(this.displayName())
              .fontSize(fs(18)).fontFamily(ff())
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT_PRIMARY)
            Text(`已记录 ${this.recordList.length.toString()} 条 · 坚持 ${distinctDayCount(this.recordList).toString()} 天`)
              .fontSize(fs(12)).fontFamily(ff())
              .fontColor(TEXT_SECONDARY)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text('编辑')
            .fontSize(fs(13)).fontFamily(ff())
            .fontColor(APP_THEME_COLOR)
            .backgroundColor(CHIP_BG)
            .borderRadius(14)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        }
        .width('100%')
        .cardLook()
        .onClick(() => {
          this.isShowProfileSheet = true
        })

        // 功能列表
        Column() {
          this.menuRow('⚙️', '设置', (): void => {
            this.pathStack.pushPathByName('SettingsPage', '')
          })
          Divider()
            .color(CARD_DIVIDER_COLOR)
            .width('100%')
          this.menuRow('📋', '模板管理', (): void => {
            this.pathStack.pushPathByName('TemplateManagePage', '')
          })
          Divider()
            .color(CARD_DIVIDER_COLOR)
            .width('100%')
          this.menuRow('💾', '数据管理', (): void => {
            this.pathStack.pushPathByName('DataManagePage', '')
          })
          Divider()
            .color(CARD_DIVIDER_COLOR)
            .width('100%')
          this.menuRow('ℹ️', '关于', (): void => {
            this.pathStack.pushPathByName('AboutPage', '')
          })
        }
        .width('100%')
        .cardLook()
      }
      .padding({ left: 16, right: 16, top: 12, bottom: 24 })
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .bindSheet($$this.isShowProfileSheet, this.profileSheetBuilder, {
      detents: [SheetSize.MEDIUM],
      dragBar: true,
      showClose: false,
      backgroundColor: Color.White
    })
  }

  displayName(): string {
    if (this.userName !== '') {
      return this.userName
    }
    return '未设置昵称'
  }

  @Builder
  profileSheetBuilder() {
    Column() {
      Text('编辑个人信息')
        .fontSize(fs(18)).fontFamily(ff())
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_PRIMARY)
        .width('100%')
        .margin({ top: 16 })
      ProfileEditor({
        onSaved: () => {
          this.isShowProfileSheet = false
        }
      })
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
    .backgroundColor(Color.White)
  }

  @Builder
  menuRow(icon: string, label: string, action: () => void) {
    Row() {
      Text(icon)
        .fontSize(fs(18)).fontFamily(ff())
      Text(label)
        .fontSize(fs(15)).fontFamily(ff())
        .fontColor(TEXT_PRIMARY)
        .margin({ left: 12 })
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text('›')
        .fontSize(fs(18)).fontFamily(ff())
        .fontColor('#C4C9D0')
    }
    .width('100%')
    .height(52)
    .padding({ left: 4, right: 4 })
    .onClick(() => {
      action()
    })
  }
}

// ============================= 摘要详情二级页 =============================
@Component
struct SummaryDetailPage {
  @StorageLink('fontSizeIndex') fontSizeIndex: number = 1
  filterKind: string = 'today'
  @StorageLink('allRecords') recordList: RecordItem[] = []

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 10 }) {
          if (this.getFilteredList().length === 0) {
            Text('暂无相关记录')
              .fontSize(fs(14)).fontFamily(ff())
              .fontColor(TEXT_SECONDARY)
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ top: 64 })
          }
          ForEach(this.getFilteredList(), (rec: RecordItem) => {
            RecordCard({ rec: rec })
          }, (rec: RecordItem) => `record_${rec.id.toString()}`)
        }
        .padding({ left: 16, right: 16, top: 12, bottom: 24 })
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .title(this.getTitle())
    .backgroundColor(PAGE_BG)
  }

  getTitle(): string {
    if (this.filterKind === 'today') {
      return '今日记录'
    }
    if (this.filterKind === 'week') {
      return '本周记录'
    }
    return '待提醒'
  }

  getFilteredList(): RecordItem[] {
    if (this.filterKind === 'today') {
      return this.recordList.filter((rec: RecordItem): boolean => rec.recordTime >= startOfDay(Date.now()))
        .sort((a: RecordItem, b: RecordItem): number => b.recordTime - a.recordTime)
    }
    if (this.filterKind === 'week') {
      return this.recordList.filter((rec: RecordItem): boolean => rec.recordTime >= startOfWeek())
        .sort((a: RecordItem, b: RecordItem): number => b.recordTime - a.recordTime)
    }
    return this.recordList.filter((rec: RecordItem): boolean => rec.remindAt > Date.now())
      .sort((a: RecordItem, b: RecordItem): number => a.remindAt - b.remindAt)
  }
}

// ============================= 设置二级页 =============================
@Component
struct SettingsPage {
  @StorageLink('appearanceMode') appearanceIndex: number = 2
  @StorageLink('fontSizeIndex') fontSizeIndex: number = 1
  @StorageLink('fontFamilyIndex') fontFamilyIndex: number = 0

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 12 }) {
          // 背景外观
          Column() {
            Text('背景外观')
              .fontSize(fs(16)).fontFamily(ff())
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT_PRIMARY)
              .width('100%')
            Text('选择应用的背景颜色主题，切换后立即对所有页面生效')
              .fontSize(fs(12)).fontFamily(ff())
              .fontColor(TEXT_SECONDARY)
              .width('100%')
              .margin({ top: 4 })
            Row() {
              Text('外观模式')
                .fontSize(fs(15)).fontFamily(ff())
                .fontColor(TEXT_PRIMARY)
              Blank()
              Select(this.getAppearanceOptions())
                .selected(this.appearanceIndex)
                .value(this.getAppearanceLabel())
                .font({ size: 14 })
                .fontColor(TEXT_PRIMARY)
                .constraintSize({ maxWidth: 150 })
                .onSelect((index: number) => {
                  this.appearanceIndex = index
                  this.showToast(`已切换为「${this.getAppearanceLabel()}」`)
                })
            }
            .width('100%')
            .margin({ top: 12 })

            Row() {
              Column() {
                Text('预览效果')
                  .fontSize(fs(14)).fontFamily(ff())
                  .fontColor(this.getPreviewTextColor())
              }
              .width('100%')
              .height(80)
              .borderRadius(12)
              .backgroundColor(this.getPreviewBgColor())
              .border({ width: 1, color: '#E5E8EC' })
              .justifyContent(FlexAlign.Center)
            }
            .width('100%')
            .margin({ top: 12 })
          }
          .width('100%')
          .cardLook()

          // 字体设置
          Column() {
            Text('字体设置')
              .fontSize(fs(16)).fontFamily(ff())
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT_PRIMARY)
              .width('100%')
            Text('调整应用内文字的字体与大小，保存后对所有页面生效')
              .fontSize(fs(12)).fontFamily(ff())
              .fontColor(TEXT_SECONDARY)
              .width('100%')
              .margin({ top: 4 })

            Row() {
              Text('字体')
                .fontSize(fs(15)).fontFamily(ff())
                .fontColor(TEXT_PRIMARY)
              Blank()
              Select(this.getFontFamilyOptions())
                .selected(this.fontFamilyIndex)
                .value(this.getFontFamilyLabel())
                .font({ size: 14 })
                .fontColor(TEXT_PRIMARY)
                .constraintSize({ maxWidth: 150 })
                .onSelect((index: number) => {
                  this.fontFamilyIndex = index
                  this.showToast(`字体已切换为「${this.getFontFamilyLabel()}」`)
                })
            }
            .width('100%')
            .margin({ top: 12 })

            Row() {
              Text('字体大小')
                .fontSize(fs(15)).fontFamily(ff())
                .fontColor(TEXT_PRIMARY)
              Blank()
              Select(this.getFontSizeOptions())
                .selected(this.fontSizeIndex)
                .value(this.getFontSizeLabel())
                .font({ size: 14 })
                .fontColor(TEXT_PRIMARY)
                .constraintSize({ maxWidth: 150 })
                .onSelect((index: number) => {
                  this.fontSizeIndex = index
                  this.showToast(`字体大小已切换为「${this.getFontSizeLabel()}」`)
                })
            }
            .width('100%')
            .margin({ top: 12 })

            Row() {
              Column() {
                Text('预览效果 Aa 汉字 123')
                  .fontSize(fs(16))
                  .fontFamily(ff())
                  .fontColor(this.getPreviewTextColor())
              }
              .width('100%')
              .height(64)
              .borderRadius(12)
              .backgroundColor(this.getPreviewBgColor())
              .border({ width: 1, color: '#E5E8EC' })
              .justifyContent(FlexAlign.Center)
            }
            .width('100%')
            .margin({ top: 12 })
          }
          .width('100%')
          .cardLook()
        }
        .padding(16)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .title('设置')
    .backgroundColor(this.themeBg())
  }

  themeBg(): ResourceColor {
    if (this.appearanceIndex === 0) {
      return PAGE_BG
    }
    if (this.appearanceIndex === 1) {
      return '#0F1114'
    }
    return $r('app.color.app_background')
  }

  getAppearanceOptions(): SelectOption[] {
    return APPEARANCE_LABELS.map((label: string): SelectOption => {
      return { value: label }
    })
  }

  getAppearanceLabel(): string {
    return APPEARANCE_LABELS[this.appearanceIndex]
  }

  getFontFamilyOptions(): SelectOption[] {
    return FONT_FAMILY_LABELS.map((label: string): SelectOption => {
      return { value: label }
    })
  }

  getFontFamilyLabel(): string {
    return FONT_FAMILY_LABELS[this.fontFamilyIndex]
  }

  getFontSizeOptions(): SelectOption[] {
    return FONT_SIZE_LABELS.map((label: string): SelectOption => {
      return { value: label }
    })
  }

  getFontSizeLabel(): string {
    return FONT_SIZE_LABELS[this.fontSizeIndex]
  }

  getPreviewBgColor(): string {
    if (this.appearanceIndex === 0) {
      return '#FFFFFF'
    }
    if (this.appearanceIndex === 1) {
      return '#111111'
    }
    return PAGE_BG
  }

  getPreviewTextColor(): string {
    if (this.appearanceIndex === 1) {
      return '#FFFFFF'
    }
    return TEXT_PRIMARY
  }

  showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }
}

// ============================= 模板管理二级页 =============================
@Component
struct TemplateManagePage {
  @StorageLink('fontSizeIndex') fontSizeIndex: number = 1
  @StorageLink('allTemplates') templateList: TemplateItem[] = []
  @StorageLink('appearanceMode') appearanceIndex: number = 2
  @State isShowEditSheet: boolean = false
  @State editNameText: string = ''
  @State editSubTitleText: string = ''
  @State editAmountText: string = ''
  @State editUnitText: string = ''
  @State editContentText: string = ''
  @State editNoteText: string = ''
  @State editingTemplateId: number = -1

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 10 }) {
          if (this.templateList.length === 0) {
            Text('暂无模板')
              .fontSize(fs(14)).fontFamily(ff())
              .fontColor(TEXT_SECONDARY)
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ top: 64 })
          }
          ForEach(this.templateList, (tpl: TemplateItem) => {
            Row({ space: 12 }) {
              Column() {
                Text(tpl.icon)
                  .fontSize(fs(22)).fontFamily(ff())
              }
              .width(44)
              .height(44)
              .borderRadius(22)
              .backgroundColor('#F0F4FA')
              .justifyContent(FlexAlign.Center)

              Column({ space: 2 }) {
                Text(tpl.name)
                  .fontSize(fs(15)).fontFamily(ff())
                  .fontColor(TEXT_PRIMARY)
                Text(this.templateSummary(tpl))
                  .fontSize(fs(12)).fontFamily(ff())
                  .fontColor(TEXT_SECONDARY)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`已使用 ${tpl.usageCount.toString()} 次`)
                  .fontSize(fs(12)).fontFamily(ff())
                  .fontColor(TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text('编辑')
                .fontSize(fs(13)).fontFamily(ff())
                .fontColor(APP_THEME_COLOR)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .onClick(() => {
                  this.openEditSheet(tpl)
                })
              Text('删除')
                .fontSize(fs(13)).fontFamily(ff())
                .fontColor('#E8402F')
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .onClick(() => {
                  this.deleteTemplate(tpl.id)
                })
            }
            .width('100%')
            .cardLook()
          }, (tpl: TemplateItem) => `${tpl.id.toString()}_${tpl.usageCount.toString()}_${tpl.subTitle}_${tpl.amount}_${tpl.unit}_${tpl.content}_${tpl.note}`)
        }
        .padding(16)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .bindSheet($$this.isShowEditSheet, this.editSheetBuilder, {
        detents: [SheetSize.LARGE],
        dragBar: true,
        showClose: false,
        backgroundColor: Color.White
      })
    }
    .title('模板管理')
    .backgroundColor(PAGE_BG)
  }

  templateSummary(tpl: TemplateItem): string {
    const parts: string[] = []
    if (tpl.subTitle !== '') {
      parts.push(tpl.subTitle)
    }
    if (tpl.amount !== '') {
      if (tpl.unit !== '') {
        parts.push(`数值：${tpl.amount} ${tpl.unit}`)
      } else {
        parts.push(`数值：${tpl.amount}`)
      }
    }
    if (tpl.content !== '') {
      parts.push(tpl.content)
    }
    if (parts.length === 0) {
      if (tpl.note !== '') {
        return `备注：${tpl.note}`
      }
      return '未设置正文与备注'
    }
    return parts.join(' · ')
  }

  openEditSheet(tpl: TemplateItem): void {
    this.editingTemplateId = tpl.id
    this.editNameText = tpl.name
    this.editSubTitleText = tpl.subTitle
    this.editAmountText = tpl.amount
    this.editUnitText = tpl.unit
    this.editContentText = tpl.content
    this.editNoteText = tpl.note
    this.isShowEditSheet = true
  }

  saveTemplateEdit(): void {
    const name = this.editNameText.trim()
    if (name === '') {
      this.showToast('模板名称不能为空')
      return
    }
    const updated: TemplateItem[] =
      this.templateList.map((tpl: TemplateItem): TemplateItem => {
        if (tpl.id === this.editingTemplateId) {
          return new TemplateItem(tpl.id, name, this.editSubTitleText.trim(), tpl.icon, tpl.usageCount,
            this.editAmountText.trim(), this.editUnitText.trim(), this.editContentText, this.editNoteText,
            tpl.extraLevels)
        }
        return tpl
      })
    this.templateList = updated
    this.isShowEditSheet = false
    this.showToast('模板已保存')
  }

  @Builder
  editSheetBuilder() {
    Scroll() {
      Column({ space: 14 }) {
        Text('编辑模板')
          .fontSize(fs(18)).fontFamily(ff())
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .width('100%')
          .margin({ top: 16 })

        Column({ space: 8 }) {
          Text('模板名称')
            .fontSize(fs(14)).fontFamily(ff())
            .fontColor(TEXT_SECONDARY)
            .width('100%')
          TextInput({ placeholder: '请输入模板名称', text: this.editNameText })
            .height(44)
            .width('100%')
            .onChange((value: string) => {
              this.editNameText = value
            })
        }
        .width('100%')

        Column({ space: 8 }) {
          Text('二级标题')
            .fontSize(fs(14)).fontFamily(ff())
            .fontColor(TEXT_SECONDARY)
            .width('100%')
          TextInput({ placeholder: '选填', text: this.editSubTitleText })
            .height(44)
            .width('100%')
            .onChange((value: string) => {
              this.editSubTitleText = value
            })
        }
        .width('100%')

        Row({ space: 12 }) {
          Column({ space: 8 }) {
            Text('数值')
              .fontSize(fs(14)).fontFamily(ff())
              .fontColor(TEXT_SECONDARY)
              .width('100%')
            TextInput({ placeholder: '选填', text: this.editAmountText })
              .height(44)
              .width('100%')
              .onChange((value: string) => {
                this.editAmountText = value
              })
          }
          .layoutWeight(1)

          Column({ space: 8 }) {
            Text('单位')
              .fontSize(fs(14)).fontFamily(ff())
              .fontColor(TEXT_SECONDARY)
              .width('100%')
            TextInput({ placeholder: '如：ml', text: this.editUnitText })
              .height(44)
              .width('100%')
              .onChange((value: string) => {
                this.editUnitText = value
              })
          }
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)

        Column({ space: 8 }) {
          Text('正文')
            .fontSize(fs(14)).fontFamily(ff())
            .fontColor(TEXT_SECONDARY)
            .width('100%')
          TextArea({ placeholder: '请输入正文内容', text: this.editContentText })
            .height(80)
            .width('100%')
            .onChange((value: string) => {
              this.editContentText = value
            })
        }
        .width('100%')

        Column({ space: 8 }) {
          Text('备注')
            .fontSize(fs(14)).fontFamily(ff())
            .fontColor(TEXT_SECONDARY)
            .width('100%')
          TextArea({ placeholder: '请输入备注', text: this.editNoteText })
            .height(60)
            .width('100%')
            .onChange((value: string) => {
              this.editNoteText = value
            })
        }
        .width('100%')

        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .height(44)
            .fontSize(fs(15)).fontFamily(ff())
            .backgroundColor('#E8EBF0')
            .fontColor(TEXT_PRIMARY)
            .onClick(() => {
              this.isShowEditSheet = false
            })
          Button('保存')
            .layoutWeight(1)
            .height(44)
            .fontSize(fs(15)).fontFamily(ff())
            .backgroundColor(APP_THEME_COLOR)
            .onClick(() => {
              this.saveTemplateEdit()
            })
        }
        .width('100%')
        .margin({ top: 4, bottom: 24 })
      }
      .width('100%')
      .padding({ left: 20, right: 20 })
    }
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .backgroundColor(Color.White)
  }

  deleteTemplate(id: number): void {
    const updated: TemplateItem[] =
      this.templateList.filter((tpl: TemplateItem): boolean => tpl.id !== id)
    this.templateList = updated
    this.showToast('模板已删除')
  }

  showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }
}

// ============================= 数据管理二级页 =============================
@Component
struct DataManagePage {
  @StorageLink('fontSizeIndex') fontSizeIndex: number = 1
  @StorageLink('allRecords') recordList: RecordItem[] = []
  @StorageLink('allTemplates') templateList: TemplateItem[] = []
  @StorageLink('appearanceMode') appearanceIndex: number = 2
  @State exportRangeIndex: number = 0
  @State customStart: Date = new Date(Date.now() - 7 * 86400000)
  @State customEnd: Date = new Date()
  @State mainTitleIndex: number = 0
  @State subTitleIndex: number = 0

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 12 }) {
          // 重置所有数据
          Column() {
            Text('重置所有数据')
              .fontSize(fs(16)).fontFamily(ff())
              .fontWeight(FontWeight.Bold)
              .fontColor('#E8402F')
              .width('100%')
            Text('清空全部记录与模板数据，操作不可恢复，请谨慎操作。')
              .fontSize(fs(12)).fontFamily(ff())
              .fontColor(TEXT_SECONDARY)
              .width('100%')
              .margin({ top: 4 })
            Button('重置所有数据')
              .width('100%')
              .height(42)
              .fontSize(fs(14)).fontFamily(ff())
              .backgroundColor('#E8402F')
              .margin({ top: 14 })
              .onClick(() => {
                this.confirmReset()
              })
          }
          .width('100%')
          .cardLook()

          // 时间范围
          Column() {
            Row() {
              Text('时间范围')
                .fontSize(fs(15)).fontFamily(ff())
                .fontColor(TEXT_PRIMARY)
              Blank()
              Select(this.getRangeOptions())
                .selected(this.exportRangeIndex)
                .value(this.getRangeLabel())
                .font({ size: 14 })
                .fontColor(TEXT_PRIMARY)
                .constraintSize({ maxWidth: 160 })
                .onSelect((index: number) => {
                  this.exportRangeIndex = index
                })
            }
            .width('100%')

            if (this.exportRangeIndex === 3) {
              Column() {
                Text('开始日期')
                  .fontSize(fs(13)).fontFamily(ff())
                  .fontColor(TEXT_SECONDARY)
                  .width('100%')
                  .margin({ bottom: 4 })
                DatePicker({
                  start: new Date(2020, 0, 1),
                  end: new Date(2030, 11, 31),
                  selected: this.customStart
                })
                  .onDateChange((value: Date) => {
                    this.customStart = value
                  })

                Text('结束日期')
                  .fontSize(fs(13)).fontFamily(ff())
                  .fontColor(TEXT_SECONDARY)
                  .width('100%')
                  .margin({ top: 12, bottom: 4 })
                DatePicker({
                  start: new Date(2020, 0, 1),
                  end: new Date(2030, 11, 31),
                  selected: this.customEnd
                })
                  .onDateChange((value: Date) => {
                    this.customEnd = value
                  })
              }
              .width('100%')
              .margin({ top: 12 })
            }
          }
          .width('100%')
          .cardLook()

          // 一级标题
          Column() {
            Row() {
              Text('一级标题')
                .fontSize(fs(15)).fontFamily(ff())
                .fontColor(TEXT_PRIMARY)
              Blank()
              Select(this.getMainTitleOptions())
                .selected(this.mainTitleIndex)
                .value(this.getMainTitleLabel())
                .font({ size: 14 })
                .fontColor(TEXT_PRIMARY)
                .constraintSize({ maxWidth: 160 })
                .onSelect((index: number) => {
                  this.mainTitleIndex = index
                  this.subTitleIndex = 0
                })
            }
            .width('100%')
          }
          .width('100%')
          .cardLook()

          // 二级标题
          Column() {
            Row() {
              Text('二级标题')
                .fontSize(fs(15)).fontFamily(ff())
                .fontColor(TEXT_PRIMARY)
              Blank()
              Select(this.getSubTitleOptions())
                .selected(this.subTitleIndex)
                .value(this.getSubTitleLabel())
                .font({ size: 14 })
                .fontColor(TEXT_PRIMARY)
                .constraintSize({ maxWidth: 160 })
                .onSelect((index: number) => {
                  this.subTitleIndex = index
                })
            }
            .width('100%')
          }
          .width('100%')
          .cardLook()

          // 导出为 Excel
          Button('导出为 Excel')
            .width('100%')
            .height(48)
            .fontSize(fs(16)).fontFamily(ff())
            .backgroundColor(APP_THEME_COLOR)
            .margin({ top: 4 })
            .onClick(() => {
              this.exportToExcel()
            })

          Text(`当前筛选条件下共 ${this.getFilteredRecords().length.toString()} 条记录`)
            .fontSize(fs(12)).fontFamily(ff())
            .fontColor(TEXT_SECONDARY)
            .width('100%')
            .textAlign(TextAlign.Center)
        }
        .padding(16)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .title('数据管理')
    .backgroundColor(this.themeBg())
  }

  themeBg(): ResourceColor {
    if (this.appearanceIndex === 0) {
      return PAGE_BG
    }
    if (this.appearanceIndex === 1) {
      return '#0F1114'
    }
    return $r('app.color.app_background')
  }

  getRangeOptions(): SelectOption[] {
    return EXPORT_RANGE_LABELS.map((label: string): SelectOption => {
      return { value: label }
    })
  }

  getRangeLabel(): string {
    return EXPORT_RANGE_LABELS[this.exportRangeIndex]
  }

  getTitleNames(): string[] {
    const titles: string[] = this.recordList.map((rec: RecordItem): string => rec.title)
    const result: string[] = ['全部']
    distinctValues(titles).forEach((title: string) => {
      result.push(title)
    })
    return result
  }

  getMainTitleOptions(): SelectOption[] {
    return this.getTitleNames().map((name: string): SelectOption => {
      return { value: name }
    })
  }

  getMainTitleLabel(): string {
    return this.getTitleNames()[this.mainTitleIndex]
  }

  getSubTitleNames(): string[] {
    const mainTitle = this.getTitleNames()[this.mainTitleIndex]
    const source: RecordItem[] = mainTitle === '全部' ? this.recordList :
      this.recordList.filter((rec: RecordItem): boolean => rec.title === mainTitle)
    const subTitles: string[] = source.map((rec: RecordItem): string => rec.subTitle)
    const result: string[] = ['全部']
    distinctValues(subTitles).forEach((subTitle: string) => {
      result.push(subTitle)
    })
    return result
  }

  getSubTitleOptions(): SelectOption[] {
    return this.getSubTitleNames().map((name: string): SelectOption => {
      return { value: name }
    })
  }

  getSubTitleLabel(): string {
    return this.getSubTitleNames()[this.subTitleIndex]
  }

  getFilteredRecords(): RecordItem[] {
    let since = 0
    let until = endOfDay(Date.now())
    if (this.exportRangeIndex === 1) {
      since = Date.now() - 7 * 86400000
    } else if (this.exportRangeIndex === 2) {
      since = Date.now() - 30 * 86400000
    } else if (this.exportRangeIndex === 3) {
      since = startOfDay(this.customStart.getTime())
      until = endOfDay(this.customEnd.getTime())
    }
    const mainTitle = this.getTitleNames()[this.mainTitleIndex]
    const subTitle = this.getSubTitleNames()[this.subTitleIndex]
    return this.recordList.filter((rec: RecordItem): boolean => {
      if (rec.recordTime < since || rec.recordTime > until) {
        return false
      }
      if (mainTitle !== '全部' && rec.title !== mainTitle) {
        return false
      }
      if (subTitle !== '全部' && rec.subTitle !== subTitle) {
        return false
      }
      return true
    })
  }

  csvCell(value: string): string {
    if (value.indexOf(',') >= 0 || value.indexOf('"') >= 0 || value.indexOf('\n') >= 0) {
      return `"${value.replace(/"/g, '""')}"`
    }
    return value
  }

  buildCsvText(rows: RecordItem[]): string {
    let text = '\uFEFFID,一级标题,二级标题,数值,单位,内容,备注,标签,记录时间,提醒时间\n'
    rows.forEach((rec: RecordItem) => {
      const cells: string[] = [
        rec.id.toString(),
        this.csvCell(rec.title),
        this.csvCell(rec.subTitle),
        this.csvCell(rec.amount),
        this.csvCell(rec.unit),
        this.csvCell(rec.content),
        this.csvCell(rec.note),
        this.csvCell(rec.tags.join('|')),
        this.csvCell(formatFull(rec.recordTime)),
        rec.remindAt > 0 ? this.csvCell(formatFull(rec.remindAt)) : ''
      ]
      text += cells.join(',') + '\n'
    })
    return text
  }

  buildCsvFileName(): string {
    const now = new Date()
    const stamp = `${now.getFullYear().toString()}${pad2(now.getMonth() + 1)}${pad2(now.getDate())}` +
      `_${pad2(now.getHours())}${pad2(now.getMinutes())}${pad2(now.getSeconds())}`
    return `records_${stamp}.csv`
  }

  exportToExcel(): void {
    const rows = this.getFilteredRecords()
    if (rows.length === 0) {
      this.showToast('当前筛选条件下没有可导出的记录')
      return
    }
    const context = getContext(this)
    const fileName = this.buildCsvFileName()
    const dirPath = context.filesDir
    const filePath = `${dirPath}/${fileName}`
    try {
      const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      fileIo.writeSync(file.fd, this.buildCsvText(rows))
      fileIo.closeSync(file)
      AlertDialog.show({
        title: '导出成功',
        message: `已导出 ${rows.length.toString()} 条记录。\n\n文件名：${fileName}\n保存位置：${dirPath}`,
        autoCancel: true,
        alignment: DialogAlignment.Bottom,
        confirm: {
          value: '知道了',
          action: (): void => {
          }
        }
      })
    } catch (error) {
      this.showToast('导出失败，请重试')
    }
  }

  confirmReset(): void {
    AlertDialog.show({
      title: '重置所有数据',
      message: `将清空全部 ${this.recordList.length.toString()} 条记录和 ${this.templateList.length.toString()} 个模板，操作不可恢复。确定继续吗？`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '重置',
        fontColor: '#E8402F',
        action: (): void => {
          this.resetAllData()
        }
      }
    })
  }

  resetAllData(): void {
    this.recordList = []
    this.templateList = []
    this.mainTitleIndex = 0
    this.subTitleIndex = 0
    this.showToast('已重置所有数据')
  }

  showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }
}

// ============================= 关于二级页 =============================
@Component
struct AboutPage {
  @StorageLink('fontSizeIndex') fontSizeIndex: number = 1
  @StorageLink('appearanceMode') appearanceIndex: number = 2

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 12 }) {
          Column() {
            Column() {
              Text('📝')
                .fontSize(fs(34)).fontFamily(ff())
            }
            .width(72)
            .height(72)
            .borderRadius(36)
            .backgroundColor(CHIP_BG)
            .justifyContent(FlexAlign.Center)

            Text('事刻')
              .fontSize(fs(20)).fontFamily(ff())
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT_PRIMARY)
              .margin({ top: 12 })
            Text('一款简洁的 HarmonyOS NEXT 记录应用')
              .fontSize(fs(13)).fontFamily(ff())
              .fontColor(TEXT_SECONDARY)
              .margin({ top: 4 })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 12, bottom: 12 })
          .cardLook()

          Column() {
            Row() {
              Text('作者')
                .fontSize(fs(15)).fontFamily(ff())
                .fontColor(TEXT_PRIMARY)
              Blank()
              Text('xingxing')
                .fontSize(fs(14)).fontFamily(ff())
                .fontColor(TEXT_SECONDARY)
            }
            .width('100%')
            Divider()
              .color(CARD_DIVIDER_COLOR)
              .width('100%')
              .margin({ top: 14, bottom: 14 })
            Row() {
              Text('GitHub')
                .fontSize(fs(15)).fontFamily(ff())
                .fontColor(TEXT_PRIMARY)
              Blank()
              Text('github.com/xingxing-chu/Shike')
                .fontSize(fs(13)).fontFamily(ff())
                .fontColor(APP_THEME_COLOR)
                .decoration({ type: TextDecorationType.Underline })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .onClick(() => {
              this.openGithubLink()
            })
          }
          .width('100%')
          .cardLook()

          Column() {
            Text('打赏支持')
              .fontSize(fs(15)).fontFamily(ff())
              .fontColor(TEXT_PRIMARY)
              .width('100%')
            Image($r('app.media.reward_qr'))
              .width(160)
              .height(160)
              .borderRadius(12)
              .objectFit(ImageFit.Contain)
              .margin({ top: 12 })
            Text('扫一扫，请作者喝杯咖啡')
              .fontSize(fs(12)).fontFamily(ff())
              .fontColor(TEXT_SECONDARY)
              .margin({ top: 8 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .cardLook()
        }
        .padding(16)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .title('关于')
    .backgroundColor(this.themeBg())
  }

  openGithubLink(): void {
    const hostContext = this.getUIContext().getHostContext()
    if (hostContext === undefined) {
      this.showToast('暂时无法打开链接')
      return
    }
    const context = hostContext as common.UIAbilityContext
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: 'https://github.com/xingxing-chu/Shike',
      parameters: {
        'ohos.ability.params.showDefaultPicker': true
      }
    }
    context.startAbility(want).catch((err: BusinessError) => {
      this.showToast('打开链接失败')
    })
  }

  showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  themeBg(): ResourceColor {
    if (this.appearanceIndex === 0) {
      return PAGE_BG
    }
    if (this.appearanceIndex === 1) {
      return '#0F1114'
    }
    return $r('app.color.app_background')
  }
}

// ============================= 记录编辑二级页 =============================
@Component
struct RecordEditPage {
  @StorageLink('fontSizeIndex') fontSizeIndex: number = 1
  pathStack: NavPathStack = new NavPathStack()
  @StorageLink('allRecords') recordList: RecordItem[] = []
  @StorageLink('allTemplates') templateList: TemplateItem[] = []
  @State firstTitle: string = ''
  @State secondTitle: string = ''
  @State extraLevels: LevelInput[] = []
  @State mainText: string = ''
  @State noteText: string = ''
  @State pickedDate: Date = new Date()
  @State pickedTime: Date = new Date()
  @State showTimePickers: boolean = false
  @State willRemind: boolean = false
  @State isShowRemindSheet: boolean = false
  @State remindDate: Date = new Date()
  @State remindTime: Date = new Date()
  @State amountText: string = ''
  @State unitText: string = ''
  @StorageLink('appearanceMode') appearanceIndex: number = 2

  build() {
    NavDestination() {
      Column() {
        // 顶部标题栏：取消 / 手动记录 / 保存
        Row() {
          Text('取消')
            .fontSize(fs(16)).fontFamily(ff())
            .fontColor(TEXT_SECONDARY)
            .onClick(() => {
              this.pathStack.pop()
            })
          Blank()
          Text('手动记录')
            .fontSize(fs(17)).fontFamily(ff())
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_PRIMARY)
          Blank()
          Text('保存')
            .fontSize(fs(16)).fontFamily(ff())
            .fontWeight(FontWeight.Medium)
            .fontColor(APP_THEME_COLOR)
            .onClick(() => {
              this.saveRecord()
            })
        }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 16 })
        .backgroundColor(Color.White)

        // 表单
        Scroll() {
          Column({ space: 12 }) {
            // 记录时间
            Column() {
              Row() {
                Text('记录时间')
                  .fontSize(fs(15)).fontFamily(ff())
                  .fontColor(TEXT_PRIMARY)
                Blank()
                Text(formatFull(combineDateTime(this.pickedDate, this.pickedTime)))
                  .fontSize(fs(14)).fontFamily(ff())
                  .fontColor(APP_THEME_COLOR)
              }
              .width('100%')
              .onClick(() => {
                this.showTimePickers = !this.showTimePickers
              })

              if (this.willRemind) {
                Text(`⏰ 将于 ${formatFull(combineDateTime(this.remindDate, this.remindTime))} 提醒`)
                  .fontSize(fs(12)).fontFamily(ff())
                  .fontColor(APP_THEME_COLOR)
                  .width('100%')
                  .margin({ top: 8 })
              }

              if (this.showTimePickers) {
                Column() {
                  Text('选择日期')
                    .fontSize(fs(13)).fontFamily(ff())
                    .fontColor(TEXT_SECONDARY)
                    .width('100%')
                    .margin({ bottom: 4 })
                  DatePicker({
                    start: new Date(2020, 0, 1),
                    end: new Date(2030, 11, 31),
                    selected: this.pickedDate
                  })
                    .onDateChange((value: Date) => {
                      this.pickedDate = value
                    })
                  Text('选择时间')
                    .fontSize(fs(13)).fontFamily(ff())
                    .fontColor(TEXT_SECONDARY)
                    .width('100%')
                    .margin({ top: 12, bottom: 4 })
                  TimePicker({ selected: this.pickedTime })
                    .useMilitaryTime(true)
                    .onChange((value: TimePickerResult) => {
                      const d = new Date()
                      d.setHours(value.hour, value.minute, 0, 0)
                      this.pickedTime = d
                    })
                }
                .width('100%')
                .margin({ top: 12 })
              }
            }
            .width('100%')
            .cardLook()

            // 标题区
            Column() {
              Row({ space: 8 }) {
                Text('一级标题')
                  .fontSize(fs(15)).fontFamily(ff())
                  .fontColor(TEXT_PRIMARY)
                  .width(76)
                TextInput({ placeholder: '如：喝水、工作', text: this.firstTitle })
                  .layoutWeight(1)
                  .padding({ left: 0, right: 0 })
                  .onChange((value: string) => {
                    this.firstTitle = value
                  })
              }
              .width('100%')

              Divider()
                .color(CARD_DIVIDER_COLOR)
                .width('100%')
                .margin({ top: 12, bottom: 12 })

              Row({ space: 8 }) {
                Text('二级标题')
                  .fontSize(fs(15)).fontFamily(ff())
                  .fontColor(TEXT_PRIMARY)
                  .width(76)
                TextInput({ placeholder: '选填', text: this.secondTitle })
                  .layoutWeight(1)
                  .padding({ left: 0, right: 0 })
                  .onChange((value: string) => {
                    this.secondTitle = value
                  })
              }
              .width('100%')

              ForEach(this.extraLevels, (item: LevelInput) => {
                Column() {
                  Divider()
                    .color(CARD_DIVIDER_COLOR)
                    .width('100%')
                    .margin({ top: 12, bottom: 12 })
                  Row({ space: 8 }) {
                    Text(item.levelName)
                      .fontSize(fs(15)).fontFamily(ff())
                      .fontColor(TEXT_PRIMARY)
                      .width(76)
                    TextInput({ placeholder: '选填', text: item.levelValue })
                      .layoutWeight(1)
                      .padding({ left: 0, right: 0 })
                      .onChange((value: string) => {
                        item.levelValue = value
                      })
                  }
                  .width('100%')
                }
                .width('100%')
              }, (item: LevelInput) => item.levelName)

              Row() {
                Text('+ 增加标题')
                  .fontSize(fs(14)).fontFamily(ff())
                  .fontWeight(FontWeight.Medium)
                  .fontColor(APP_THEME_COLOR)
              }
              .width('100%')
              .height(40)
              .justifyContent(FlexAlign.Center)
              .margin({ top: 4 })
              .onClick(() => {
                this.addExtraLevel()
              })
            }
            .width('100%')
            .cardLook()

            // 数值 / 单位
            Column() {
              Row({ space: 8 }) {
                Text('数值')
                  .fontSize(fs(15)).fontFamily(ff())
                  .fontColor(TEXT_PRIMARY)
                  .width(76)
                TextInput({ placeholder: '选填，如：250', text: this.amountText })
                  .type(InputType.Number)
                  .layoutWeight(1)
                  .padding({ left: 0, right: 0 })
                  .onChange((value: string) => {
                    this.amountText = value
                  })
              }
              .width('100%')

              Divider()
                .color(CARD_DIVIDER_COLOR)
                .width('100%')
                .margin({ top: 12, bottom: 12 })

              Row({ space: 8 }) {
                Text('单位')
                  .fontSize(fs(15)).fontFamily(ff())
                  .fontColor(TEXT_PRIMARY)
                  .width(76)
                TextInput({ placeholder: '选填，如：ml / l / s / h / cm / m', text: this.unitText })
                  .layoutWeight(1)
                  .padding({ left: 0, right: 0 })
                  .onChange((value: string) => {
                    this.unitText = value
                  })
              }
              .width('100%')
            }
            .width('100%')
            .cardLook()

            // 正文
            Column() {
              Text('正文')
                .fontSize(fs(15)).fontFamily(ff())
                .fontColor(TEXT_PRIMARY)
                .width('100%')
              TextArea({ placeholder: '记录详细内容...', text: this.mainText })
                .height(96)
                .margin({ top: 8 })
                .onChange((value: string) => {
                  this.mainText = value
                })
            }
            .width('100%')
            .cardLook()

            // 备注
            Column() {
              Text('备注')
                .fontSize(fs(15)).fontFamily(ff())
                .fontColor(TEXT_PRIMARY)
                .width('100%')
              TextInput({ placeholder: '选填备注', text: this.noteText })
                .margin({ top: 8 })
                .padding({ left: 0, right: 0 })
                .onChange((value: string) => {
                  this.noteText = value
                })
            }
            .width('100%')
            .cardLook()
          }
          .padding(16)
          .width('100%')
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)

        // 底部按钮
        Row({ space: 12 }) {
          Button('⏰ 添加日历提醒', { type: ButtonType.Capsule })
            .layoutWeight(1)
            .height(44)
            .fontSize(fs(14)).fontFamily(ff())
            .backgroundColor(this.getRemindButtonBg())
            .fontColor(this.getRemindButtonTextColor())
            .onClick(() => {
              this.openRemindSheet()
            })
          Button('保存为模板', { type: ButtonType.Capsule })
            .layoutWeight(1)
            .height(44)
            .fontSize(fs(14)).fontFamily(ff())
            .backgroundColor(CHIP_BG)
            .fontColor(APP_THEME_COLOR)
            .onClick(() => {
              this.saveAsTemplate()
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .backgroundColor(Color.White)
      }
      .width('100%')
      .height('100%')
      .bindSheet($$this.isShowRemindSheet, this.remindSheetBuilder, {
        detents: [SheetSize.LARGE],
        dragBar: true,
        showClose: false,
        backgroundColor: Color.White
      })
    }
    .hideTitleBar(true)
    .backgroundColor(this.themeBg())
  }

  themeBg(): ResourceColor {
    if (this.appearanceIndex === 0) {
      return PAGE_BG
    }
    if (this.appearanceIndex === 1) {
      return '#0F1114'
    }
    return $r('app.color.app_background')
  }

  @Builder
  remindSheetBuilder() {
    Scroll() {
      Column({ space: 16 }) {
        Text('设置提醒时间')
          .fontSize(fs(18)).fontFamily(ff())
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .width('100%')

        DatePicker({
          start: new Date(2020, 0, 1),
          end: new Date(2030, 11, 31),
          selected: this.remindDate
        })
          .onDateChange((value: Date) => {
            this.remindDate = value
          })

        TimePicker({ selected: this.remindTime })
          .useMilitaryTime(true)
          .onChange((value: TimePickerResult) => {
            const d = new Date()
            d.setHours(value.hour, value.minute, 0, 0)
            this.remindTime = d
          })

        Row({ space: 12 }) {
          if (this.willRemind) {
            Button('取消提醒', { type: ButtonType.Capsule })
              .layoutWeight(1)
              .height(44)
              .fontSize(fs(14)).fontFamily(ff())
              .backgroundColor('#ECEFF3')
              .fontColor(TEXT_PRIMARY)
              .onClick(() => {
                this.cancelRemind()
              })
          }
          Button('确定', { type: ButtonType.Capsule })
            .layoutWeight(1)
            .height(44)
            .fontSize(fs(14)).fontFamily(ff())
            .backgroundColor(APP_THEME_COLOR)
            .fontColor(Color.White)
            .onClick(() => {
              this.confirmRemind()
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 36 })
    }
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .backgroundColor(Color.White)
  }

  getRemindButtonBg(): string {
    if (this.willRemind) {
      return APP_THEME_COLOR
    }
    return '#ECEFF3'
  }

  getRemindButtonTextColor(): string {
    if (this.willRemind) {
      return '#FFFFFF'
    }
    return TEXT_PRIMARY
  }

  openRemindSheet(): void {
    if (!this.willRemind) {
      this.remindDate = this.pickedDate
      this.remindTime = this.pickedTime
    }
    this.isShowRemindSheet = true
  }

  confirmRemind(): void {
    this.willRemind = true
    this.isShowRemindSheet = false
    this.showToast('已添加日历提醒')
  }

  cancelRemind(): void {
    this.willRemind = false
    this.isShowRemindSheet = false
    this.showToast('已取消提醒')
  }

  async writeCalendarEvent(record: RecordItem): Promise<void> {
    const prompt = this.getUIContext().getPromptAction()
    const context = getContext(this)
    try {
      const perms: Permissions[] = ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR']
      const atManager = abilityAccessCtrl.createAtManager()
      const result = await atManager.requestPermissionsFromUser(context, perms)
      let granted = true
      result.authResults.forEach((code: number) => {
        if (code !== 0) {
          granted = false
        }
      })
      if (!granted) {
        prompt.showToast({ message: '未授权日历权限，提醒仅保存在应用内' })
        return
      }
      const manager = calendarManager.getCalendarManager(context)
      const calendar = await manager.getCalendar()
      const event: calendarManager.Event = {
        type: calendarManager.EventType.NORMAL,
        title: this.getCalendarTitle(record),
        description: record.content,
        startTime: record.remindAt,
        endTime: record.remindAt + 30 * 60 * 1000,
        reminderTime: [0]
      }
      await calendar.addEvent(event)
      prompt.showToast({ message: '提醒已写入系统日历' })
    } catch (error) {
      prompt.showToast({ message: '写入日历失败，提醒仅保存在应用内' })
    }
  }

  getCalendarTitle(record: RecordItem): string {
    if (record.subTitle !== '') {
      return `${record.title} · ${record.subTitle}`
    }
    return record.title
  }

  addExtraLevel(): void {
    const nextIndex = this.extraLevels.length
    if (nextIndex >= EXTRA_LEVEL_NAMES.length) {
      this.showToast('最多支持八级标题')
      return
    }
    const updated: LevelInput[] = this.extraLevels.slice()
    updated.push(new LevelInput(EXTRA_LEVEL_NAMES[nextIndex]))
    this.extraLevels = updated
  }

  getExtraLevelSummary(): string {
    let summary = ''
    this.extraLevels.forEach((item: LevelInput) => {
      const v = item.levelValue.trim()
      if (v !== '') {
        if (summary !== '') {
          summary += ' / '
        }
        summary += v
      }
    })
    return summary
  }

  saveRecord(): void {
    const title = this.firstTitle.trim()
    if (title === '') {
      this.showToast('请输入一级标题')
      return
    }
    const ts = combineDateTime(this.pickedDate, this.pickedTime)
    const tags: string[] = [title]
    const secondTitle = this.secondTitle.trim()
    if (secondTitle !== '') {
      tags.push(secondTitle)
    }
    let finalNote = this.noteText
    const extraSummary = this.getExtraLevelSummary()
    if (extraSummary !== '') {
      if (finalNote === '') {
        finalNote = extraSummary
      } else {
        finalNote = `${this.noteText}（${extraSummary}）`
      }
    }
    const remindAt = this.willRemind ? combineDateTime(this.remindDate, this.remindTime) : 0
    const record = new RecordItem(nextRecordId(), title, secondTitle, this.mainText,
      finalNote, tags, ts, remindAt, this.amountText.trim(), this.unitText.trim())
    const updated: RecordItem[] = this.recordList.slice()
    updated.push(record)
    this.recordList = updated
    this.showToast('保存成功')
    if (remindAt > 0) {
      this.writeCalendarEvent(record)
    }
    this.pathStack.pop()
  }

  saveAsTemplate(): void {
    const name = this.firstTitle.trim()
    if (name === '') {
      this.showToast('请先输入一级标题')
      return
    }
    const exists = this.templateList.find((tpl: TemplateItem): boolean => tpl.name === name)
    if (exists !== undefined) {
      this.showToast('模板已存在')
      return
    }
    const extraCopy: LevelInput[] = []
    this.extraLevels.forEach((item: LevelInput) => {
      const copied = new LevelInput(item.levelName)
      copied.levelValue = item.levelValue
      extraCopy.push(copied)
    })
    const updated: TemplateItem[] = this.templateList.slice()
    updated.push(new TemplateItem(nextTemplateId(), name, this.secondTitle.trim(), '📌', 0,
      this.amountText.trim(), this.unitText.trim(), this.mainText, this.noteText, extraCopy))
    this.templateList = updated
    this.showToast(`已保存「${name}」为模板`)
  }

  showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }
}

// ============================= 主页面 =============================
@Entry
@Component
struct Index {
  @StorageLink('fontSizeIndex') fontSizeIndex: number = 1
  @State currentTabIndex: number = 0
  @State isShowQuickSheet: boolean = false
  @State isShowProfileSheet: boolean = false
  @State detailFilterKind: string = 'today'
  @StorageLink('allRecords') recordList: RecordItem[] = []
  @StorageLink('allTemplates') templateList: TemplateItem[] = []
  @StorageLink('appearanceMode') appearanceIndex: number = 2
  @StorageLink('widgetOpenQuickSheet') @Watch('onWidgetTrigger') widgetOpenQuickSheet: boolean = false
  navPathStack: NavPathStack = new NavPathStack()

  aboutToAppear(): void {
    const savedName = AppStorage.get<string>('userName')
    if (savedName === undefined || savedName === '') {
      this.isShowProfileSheet = true
    }
    if (AppStorage.get<boolean>('widgetOpenQuickSheet') === true) {
      this.isShowQuickSheet = true
      AppStorage.setOrCreate('widgetOpenQuickSheet', false)
    }
  }

  onWidgetTrigger(): void {
    if (this.widgetOpenQuickSheet) {
      this.isShowQuickSheet = true
      this.widgetOpenQuickSheet = false
    }
  }

  openSummaryDetail(kind: string): void {
    this.detailFilterKind = kind
    this.navPathStack.pushPathByName('SummaryDetail', kind)
  }

  quickAddFromTemplate(tpl: TemplateItem): void {
    let finalNote = tpl.note
    const extraSummary = this.getExtraSummary(tpl.extraLevels)
    if (extraSummary !== '') {
      if (finalNote === '') {
        finalNote = extraSummary
      } else {
        finalNote = `${tpl.note}（${extraSummary}）`
      }
    }
    const tags: string[] = [tpl.name]
    if (tpl.subTitle !== '') {
      tags.push(tpl.subTitle)
    }
    const record = new RecordItem(nextRecordId(), tpl.name, tpl.subTitle, tpl.content,
      finalNote, tags, Date.now(), 0, tpl.amount, tpl.unit)
    const updatedRecords: RecordItem[] = this.recordList.slice()
    updatedRecords.push(record)
    this.recordList = updatedRecords

    const updatedTemplates: TemplateItem[] =
      this.templateList.map((item: TemplateItem): TemplateItem => {
        if (item.id === tpl.id) {
          return new TemplateItem(item.id, item.name, item.subTitle, item.icon, item.usageCount + 1,
            item.amount, item.unit, item.content, item.note, item.extraLevels)
        }
        return item
      })
    this.templateList = updatedTemplates

    this.isShowQuickSheet = false
    this.showToast(`已记录「${tpl.name}」`)
  }

  getExtraSummary(levels: LevelInput[]): string {
    let summary = ''
    levels.forEach((item: LevelInput) => {
      const v = item.levelValue.trim()
      if (v !== '') {
        if (summary !== '') {
          summary += ' / '
        }
        summary += v
      }
    })
    return summary
  }

  @Builder
  quickSheetBuilder() {
    Column({ space: 16 }) {
      Row() {
        Text('快速记录')
          .fontSize(fs(18)).fontFamily(ff())
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
        Blank()
        Text('关闭')
          .fontSize(fs(14)).fontFamily(ff())
          .fontColor(TEXT_SECONDARY)
          .padding(4)
          .onClick(() => {
            this.isShowQuickSheet = false
          })
      }
      .width('100%')

      Column({ space: 8 }) {
        Text('最近模板')
          .fontSize(fs(13)).fontFamily(ff())
          .fontColor(TEXT_SECONDARY)
          .width('100%')
        if (this.templateList.length === 0) {
          Text('暂无模板，可在下方管理模板')
            .fontSize(fs(13)).fontFamily(ff())
            .fontColor(TEXT_SECONDARY)
            .width('100%')
            .padding({ top: 8, bottom: 8 })
        } else {
          Row({ space: 10 }) {
            ForEach(this.templateList.slice(0, 4), (tpl: TemplateItem) => {
              Column({ space: 6 }) {
                Column() {
                  Text(tpl.icon)
                    .fontSize(fs(22)).fontFamily(ff())
                }
                .width(44)
                .height(44)
                .borderRadius(22)
                .backgroundColor(CHIP_BG)
                .justifyContent(FlexAlign.Center)
                Text(tpl.name)
                  .fontSize(fs(13)).fontFamily(ff())
                  .fontColor(TEXT_PRIMARY)
              }
              .padding({ top: 10, bottom: 10, left: 14, right: 14 })
              .borderRadius(14)
              .backgroundColor('#F7F9FC')
              .onClick(() => {
                this.quickAddFromTemplate(tpl)
              })
            }, (tpl: TemplateItem) => `${tpl.id.toString()}_${tpl.usageCount.toString()}`)
          }
          .width('100%')
        }
      }
      .width('100%')

      Column() {
        Row() {
          Text('✏️')
            .fontSize(fs(18)).fontFamily(ff())
          Text('手动记录')
            .fontSize(fs(15)).fontFamily(ff())
            .fontColor(TEXT_PRIMARY)
            .margin({ left: 12 })
            .layoutWeight(1)
          Text('›')
            .fontSize(fs(18)).fontFamily(ff())
            .fontColor('#C4C9D0')
        }
        .width('100%')
        .height(52)
        .onClick(() => {
          this.isShowQuickSheet = false
          this.navPathStack.pushPathByName('RecordEditPage', '')
        })
      }
      .width('100%')
      .padding({ left: 4, right: 4 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 36 })
    .backgroundColor(Color.White)
  }

  @Builder
  profileSheetBuilder() {
    Column() {
      Text('完善个人信息')
        .fontSize(fs(18)).fontFamily(ff())
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_PRIMARY)
        .width('100%')
        .margin({ top: 16 })
      Text('设置昵称与头像，开始你的记录之旅')
        .fontSize(fs(13)).fontFamily(ff())
        .fontColor(TEXT_SECONDARY)
        .width('100%')
        .margin({ top: 4 })
      ProfileEditor({
        onSaved: () => {
          this.isShowProfileSheet = false
        }
      })
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
    .backgroundColor(Color.White)
  }

  @Builder
  pageMap(name: string) {
    if (name === 'SummaryDetail') {
      SummaryDetailPage({ filterKind: this.detailFilterKind })
    } else if (name === 'SettingsPage') {
      SettingsPage()
    } else if (name === 'TemplateManagePage') {
      TemplateManagePage()
    } else if (name === 'DataManagePage') {
      DataManagePage()
    } else if (name === 'AboutPage') {
      AboutPage()
    } else if (name === 'RecordEditPage') {
      RecordEditPage({ pathStack: this.navPathStack })
    }
  }

  build() {
    Navigation(this.navPathStack) {
      Tabs({ barPosition: BarPosition.End, index: this.currentTabIndex }) {
        TabContent() {
          HomeTab({
            onOpenSheet: () => {
              this.isShowQuickSheet = true
            },
            onOpenDetail: (kind: string) => {
              this.openSummaryDetail(kind)
            }
          })
        }
        .tabBar('首页')

        TabContent() {
          TimelineTab()
        }
        .tabBar('时间线')

        TabContent() {
          StatsTab()
        }
        .tabBar('统计')

        TabContent() {
          MineTab({ pathStack: this.navPathStack })
        }
        .tabBar('我的')
      }
      .scrollable(false)
      .barWidth('100%')
      .barHeight(56)
      .backgroundColor(this.themeBg())
      .onChange((index: number) => {
        this.currentTabIndex = index
      })
      .bindSheet($$this.isShowProfileSheet, this.profileSheetBuilder, {
        detents: [SheetSize.MEDIUM],
        dragBar: true,
        showClose: false,
        backgroundColor: Color.White
      })
    }
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .navDestination(this.pageMap)
    .bindSheet($$this.isShowQuickSheet, this.quickSheetBuilder, {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      dragBar: true,
      showClose: false,
      backgroundColor: Color.White
    })
  }

  showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  themeBg(): ResourceColor {
    if (this.appearanceIndex === 0) {
      return PAGE_BG
    }
    if (this.appearanceIndex === 1) {
      return '#0F1114'
    }
    return $r('app.color.app_background')
  }
}
