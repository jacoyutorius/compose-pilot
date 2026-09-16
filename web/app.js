const { createApp, h } = Vue;

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
        h('button', {
          type: 'button',
          disabled: this.busy || !this.service.selectable || this.running,
          onClick: () => this.$emit('run-action', 'up')
        }, '起動'),
        h('button', {
          type: 'button',
          disabled: this.busy || !this.service.selectable || !this.running,
          onClick: () => this.$emit('run-action', 'stop')
        }, '停止'),
        h('button', {
          type: 'button',
          disabled: this.busy || !this.service.selectable || !this.running,
          onClick: () => this.$emit('run-action', 'restart')
        }, '再起動')
      ]),
      h('div', { class: 'service-footer' }, [
        h('small', this.ports),
        this.openUrl ? h('a', {
          class: 'open-link',
          href: this.openUrl,
          target: '_blank',
          rel: 'noopener noreferrer'
        }, 'ブラウザで開く') : null
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
      error: ''
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
        ['build-up', 'ビルドして起動', 'primary'],
        ['build', 'ビルド', ''],
        ['restart', '再起動', ''],
        ['stop', '停止', ''],
        ['remove', '削除', 'danger']
      ];
      return h('div', [
        h('div', { class: 'title-row' }, [
          h('div', [h('h1', this.project.name), h('p', { id: 'path' }, this.project.file)]),
          h('span', { class: ['badge', { running: this.projectRunning }] }, this.projectState)
        ]),
        h('div', { class: 'actions' }, actions.map(([action, label, className]) => h('button', {
          class: className,
          disabled: this.actionInProgress,
          onClick: () => this.runAction(action)
        }, label))),
        h('h2', ['サービス ', h('small', '（未選択ならすべて）')]),
        h('div', { class: 'services' }, this.project.services.map(service => this.renderService(service))),
        h('div', { class: 'log-head' }, [
          h('h2', '実行結果'),
          h('button', { disabled: this.actionInProgress, onClick: this.followLogs }, 'ログを追跡'),
          h('button', { onClick: () => { this.output = ''; } }, '消去')
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
        h('div', [h('strong', 'Compose Pilot'), h('span', 'macOS MVP')]),
        h('button', { disabled: this.loading, onClick: this.refresh }, '再読み込み')
      ]),
      h('main', [h('section', { class: 'content' }, [content])])
    ]);
  }
}).mount('#app');
