const { createApp, h } = Vue;

const iconPaths = {
  'build-up': [
    ['path', { d: 'M12 3 4 7l8 4 8-4-8-4Z' }],
    ['path', { d: 'm4 12 8 4 8-4' }],
    ['path', { d: 'm4 17 8 4 8-4' }],
    ['path', { d: 'M18 15V9m-3 3 3-3 3 3' }]
  ],
  build: [
    ['path', { d: 'M12 3 4 7l8 4 8-4-8-4Z' }],
    ['path', { d: 'm4 12 8 4 8-4' }],
    ['path', { d: 'm4 17 8 4 8-4' }]
  ],
  play: [['path', { d: 'm8 5 11 7-11 7V5Z' }]],
  restart: [
    ['path', { d: 'M20 11a8 8 0 1 0-2.3 5.7' }],
    ['path', { d: 'M20 4v7h-7' }]
  ],
  stop: [['rect', { x: '6', y: '6', width: '12', height: '12', rx: '2' }]],
  remove: [
    ['path', { d: 'M4 7h16' }],
    ['path', { d: 'M9 7V4h6v3' }],
    ['path', { d: 'm7 7 1 13h8l1-13' }]
  ],
  refresh: [
    ['path', { d: 'M20 11a8 8 0 1 0-2.3 5.7' }],
    ['path', { d: 'M20 4v7h-7' }]
  ],
  logs: [
    ['path', { d: 'M4 5h16v14H4z' }],
    ['path', { d: 'm8 9 3 3-3 3' }],
    ['path', { d: 'M13 15h3' }]
  ],
  clear: [
    ['path', { d: 'm5 5 14 14' }],
    ['path', { d: 'm19 5-14 14' }]
  ],
  external: [
    ['path', { d: 'M14 5h5v5' }],
    ['path', { d: 'm19 5-8 8' }],
    ['path', { d: 'M17 13v6H5V7h6' }]
  ],
  sun: [
    ['circle', { cx: '12', cy: '12', r: '4' }],
    ['path', { d: 'M12 2v2m0 16v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4' }]
  ],
  moon: [
    ['path', { d: 'M20.5 14.2A8.5 8.5 0 0 1 9.8 3.5 8.5 8.5 0 1 0 20.5 14.2Z' }]
  ]
};

const AppIcon = {
  props: { name: { type: String, required: true }, size: { type: Number, default: 18 } },
  render() {
    return h('svg', {
      class: 'icon',
      width: this.size,
      height: this.size,
      viewBox: '0 0 24 24',
      fill: 'none',
      stroke: 'currentColor',
      'stroke-width': '2',
      'stroke-linecap': 'round',
      'stroke-linejoin': 'round',
      'aria-hidden': 'true'
    }, (iconPaths[this.name] || []).map(([tag, attributes]) => h(tag, attributes)));
  }
};

function iconButton(icon, label, attributes = {}) {
  return h('button', {
    ...attributes,
    class: ['icon-button', attributes.class],
    type: 'button',
    title: label,
    'aria-label': label,
    'data-tooltip': label
  }, [h(AppIcon, { name: icon })]);
}

const ServiceCard = {
  props: {
    service: { type: Object, required: true },
    selected: { type: Boolean, required: true },
    state: { type: String, required: true },
    running: { type: Boolean, required: true },
    ports: { type: String, required: true },
    openUrl: { type: String, default: '' },
    busy: { type: Boolean, required: true }
  },
  emits: ['update:selected', 'run-action'],
  render() {
    return h('article', { class: ['service', { 'self-service': this.service.self }] }, [
      h('span', { class: 'service-name' }, [
        h('input', {
          type: 'checkbox',
          checked: this.selected,
          disabled: !this.service.selectable,
          onChange: event => this.$emit('update:selected', event.target.checked)
        }),
        h('strong', this.service.name)
      ]),
      h('span', this.state),
      this.service.self ? h('small', 'Compose Pilot（通常は操作対象外）') : null,
      h('div', { class: 'service-actions' }, [
        iconButton('play', '起動', {
          disabled: this.busy || !this.service.selectable || this.running,
          onClick: () => this.$emit('run-action', 'up')
        }),
        iconButton('stop', '停止', {
          disabled: this.busy || !this.service.selectable || !this.running,
          onClick: () => this.$emit('run-action', 'stop')
        }),
        iconButton('restart', '再起動', {
          disabled: this.busy || !this.service.selectable || !this.running,
          onClick: () => this.$emit('run-action', 'restart')
        })
      ]),
      h('div', { class: 'service-footer' }, [
        h('small', this.ports),
        this.openUrl ? h('a', {
          class: ['open-link', 'icon-button'],
          href: this.openUrl,
          target: '_blank',
          rel: 'noopener noreferrer',
          title: 'ブラウザで開く',
          'aria-label': 'ブラウザで開く',
          'data-tooltip': 'ブラウザで開く'
        }, [h(AppIcon, { name: 'external' })]) : null
      ])
    ]);
  }
};

createApp({
  components: { ServiceCard },
  data() {
    return {
      project: null,
      statusRows: [],
      selectedServices: [],
      output: '操作できます。',
      actionInProgress: false,
      loading: true,
      error: '',
      theme: window.ComposePilotTheme.current()
    };
  },
  computed: {
    statusByService() {
      return Object.fromEntries(this.statusRows.map(item => [item.Service || item.Name, item]));
    },
    projectState() {
      if (!this.statusRows.length) return '停止中';
      const running = this.statusRows.filter(item => /running/i.test(item.State || '')).length;
      return `${running}/${this.statusRows.length} 起動中`;
    },
    projectRunning() {
      return this.statusRows.some(item => /running/i.test(item.State || ''));
    }
  },
  mounted() {
    this.refresh();
  },
  methods: {
    async refresh() {
      this.loading = true;
      this.error = '';
      try {
        await this.loadProject();
      } catch (error) {
        this.project = null;
        this.error = `設定を読み込めませんでした: ${error.message}`;
      } finally {
        this.loading = false;
      }
    },
    async loadProject() {
      const response = await fetch('/api/project');
      if (!response.ok) throw new Error(await response.text());

      this.project = await response.json();
      const selectable = new Set(this.project.services.filter(service => service.selectable).map(service => service.name));
      this.selectedServices = this.selectedServices.filter(name => selectable.has(name));
      await this.loadStatus();
    },
    async loadStatus() {
      const response = await fetch('/api/status');
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || '状態を取得できませんでした');

      this.statusRows = String(data.output || '').trim().split('\n').filter(Boolean).flatMap(line => {
        try {
          const parsed = JSON.parse(line);
          return Array.isArray(parsed) ? parsed : [parsed];
        } catch {
          return [];
        }
      });
    },
    serviceState(name) {
      const item = this.statusByService[name] || {};
      return /running/i.test(item.State || '') ? '起動中' : (item.State || item.Status || '停止中');
    },
    serviceRunning(name) {
      const item = this.statusByService[name] || {};
      return /running/i.test(item.State || '');
    },
    servicePorts(name) {
      const item = this.statusByService[name] || {};
      return item.Publishers?.map(port => port.PublishedPort).filter(Boolean).join(', ') || '';
    },
    serviceOpenUrl(service) {
      if (!service.open) return '';
      const item = this.statusByService[service.name] || {};
      if (!/running/i.test(item.State || '')) return '';

      const publisher = item.Publishers?.find(port =>
        String(port.Protocol || 'tcp').toLowerCase() === 'tcp' &&
        Number(port.TargetPort) === service.open.targetPort &&
        Number(port.PublishedPort) > 0
      );
      if (!publisher) return '';

      return `${service.open.scheme}://${window.location.hostname}:${publisher.PublishedPort}${service.open.path}`;
    },
    setServiceSelected(name, selected) {
      if (selected) {
        if (!this.selectedServices.includes(name)) this.selectedServices.push(name);
      } else {
        this.selectedServices = this.selectedServices.filter(selectedName => selectedName !== name);
      }
    },
    toggleTheme() {
      this.theme = this.theme === 'dark' ? 'light' : 'dark';
      window.ComposePilotTheme.apply(this.theme);
    },
    async runAction(action, services = this.selectedServices) {
      if (this.actionInProgress || !this.project) return;
      const includesSelf = this.project.services.some(service => service.self && services.includes(service.name));
      if (includesSelf && !window.confirm('Compose Pilot自身が停止または再作成され、画面との接続が切れる可能性があります。実行しますか？')) return;

      this.actionInProgress = true;
      this.output = '処理を開始しています…\n';
      try {
        const response = await fetch('/api/actions', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ action, services })
        });
        if (!response.ok) throw new Error(await response.text());
        await this.readStream(response);
        await this.loadStatus();
      } catch (error) {
        this.output += `\nエラー: ${error.message}\n`;
      } finally {
        this.actionInProgress = false;
      }
    },
    async followLogs() {
      if (this.actionInProgress) return;
      this.output = '';
      this.actionInProgress = true;
      try {
        const response = await fetch('/api/logs');
        if (!response.ok) throw new Error(await response.text());
        await this.readStream(response);
      } catch (error) {
        this.output += `\nエラー: ${error.message}\n`;
      } finally {
        this.actionInProgress = false;
      }
    },
    async readStream(response) {
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        this.output += decoder.decode(value, { stream: true });
        await this.$nextTick();
        if (this.$refs.output) this.$refs.output.scrollTop = this.$refs.output.scrollHeight;
      }
    },
    renderService(service) {
      return h(ServiceCard, {
        key: service.name,
        service,
        selected: this.selectedServices.includes(service.name),
        state: this.serviceState(service.name),
        running: this.serviceRunning(service.name),
        ports: this.servicePorts(service.name),
        openUrl: this.serviceOpenUrl(service),
        busy: this.actionInProgress,
        'onUpdate:selected': selected => this.setServiceSelected(service.name, selected),
        onRunAction: action => this.runAction(action, [service.name])
      });
    },
    renderDetail() {
      const actions = [
        ['build-up', 'build-up', 'ビルドして起動', 'primary'],
        ['build', 'build', 'ビルド', ''],
        ['restart', 'restart', '再起動', ''],
        ['stop', 'stop', '停止', ''],
        ['remove', 'remove', '削除', 'danger']
      ];
      return h('div', [
        h('div', { class: 'title-row' }, [
          h('div', [h('h1', this.project.name), h('p', { id: 'path' }, this.project.file)]),
          h('span', { class: ['badge', { running: this.projectRunning }] }, this.projectState)
        ]),
        h('div', { class: 'actions' }, actions.map(([action, icon, label, className]) => iconButton(icon, label, {
          class: className,
          disabled: this.actionInProgress,
          onClick: () => this.runAction(action)
        }))),
        h('h2', ['サービス ', h('small', '（未選択ならすべて）')]),
        h('div', { class: 'services' }, this.project.services.map(service => this.renderService(service))),
        h('div', { class: 'log-head' }, [
          h('h2', '実行結果'),
          iconButton('logs', 'ログを追跡', { disabled: this.actionInProgress, onClick: this.followLogs }),
          iconButton('clear', '実行結果を消去', { onClick: () => { this.output = ''; } })
        ]),
        h('pre', { ref: 'output' }, this.output)
      ]);
    }
  },
  render() {
    let content;
    if (this.loading) content = h('div', { class: 'empty' }, '読み込んでいます…');
    else if (this.error) content = h('div', { class: 'empty' }, this.error);
    else content = this.renderDetail();

    return h('div', { class: 'app-shell' }, [
      h('header', [
        h('div', { class: 'brand' }, [
          h('img', { src: '/logo.svg', width: '34', height: '34', alt: '' }),
          h('div', [h('strong', 'Compose Pilot'), h('span', 'macOS MVP')])
        ]),
        h('div', { class: 'header-actions' }, [
          iconButton(
            this.theme === 'dark' ? 'sun' : 'moon',
            this.theme === 'dark' ? 'ライトモードに切り替え' : 'ダークモードに切り替え',
            { onClick: this.toggleTheme }
          ),
          iconButton('refresh', '再読み込み', { disabled: this.loading, onClick: this.refresh })
        ])
      ]),
      h('main', [h('section', { class: 'content' }, [content])])
    ]);
  }
}).mount('#app');
