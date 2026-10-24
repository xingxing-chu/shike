let storage = new LocalStorage();

@Entry(storage)
@Component
struct RecordWidgetCard {
  build() {
    Row({ space: 10 }) {
      Column() {
        Text('📝')
          .fontSize(20)
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor('#FFFFFF')
      .opacity(0.92)
      .justifyContent(FlexAlign.Center)

      Column({ space: 2 }) {
        Text('记一笔')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
        Text('点击开始记录')
          .fontSize(10)
          .fontColor('#D9E8FF')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .borderRadius(16)
    .backgroundColor('#007DFF')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 12, right: 12 })
    .onClick(() => {
      postCardAction(this, {
        'action': 'router',
        'abilityName': 'EntryAbility',
        'params': {
          'openQuickSheet': 'true'
        }
      });
    })
  }
}
