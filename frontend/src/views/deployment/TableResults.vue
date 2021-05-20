<template>
  <div class="container">
    <b-collapse
      class="card"
      animation="slide"
      :open="false">
      <template #trigger="props">
        <div class="card-header" role="button">
          <div class="card-header-title is-justify-content-space-between">
            <b-field grouped>
              <b-field v-if="enableSwitches" label="Deploy" custom-class="is-size-7">
                <b-switch size="is-small" @click.native.stop v-model="table.deploy"/>
              </b-field>
              <b-field label="Table" custom-class="is-size-7">
                {{table.tableName}}
              </b-field>
            </b-field>
            <div>
              <label class="label is-size-7">{{table.successfulTriggers.length}} Successful</label>
              <label class="label is-size-7" :class="{'has-text-danger': table.erroneousTriggers.length > 0}">
                {{table.erroneousTriggers.length}} Erroneous
              </label>
              <label class="label is-size-7">{{table.loadSql !== '' ? '1' : '0'}} Load SQL</label>
            </div>
          </div>
          <a class="card-header-icon">
            <b-icon
              :icon="props.open ? 'menu-down' : 'menu-up'">
            </b-icon>
          </a>
        </div>
      </template>
      <div class="card-content">
        <div v-for="(trigger, index) in table.successfulTriggers" :key="index" class="columns result-entry">
          <div class="column is-3">{{trigger.triggerName}}</div>
          <div class="column is-9">
            <pre>{{trigger.triggerSql}}</pre>
          </div>
        </div>
        <div v-for="(trigger, index) in table.erroneousTriggers" :key="index" class="columns result-entry">
          <div class="column is-3 has-text-danger">{{trigger.triggerName}}</div>
          <div class="column is-9">
            <pre>{{trigger.exceptionClass}}</pre>
            <pre>{{trigger.exceptionMessage}}</pre>
            <pre>{{trigger.triggerSql}}</pre>
          </div>
        </div>
        <div v-if="table.loadSql" class="columns result-entry">
          <div class="column is-3">Load SQL</div>
          <div class="column is-9">
            <pre>{{table.loadSql}}</pre>
          </div>
        </div>
      </div>
    </b-collapse>
  </div>
</template>

<script>
export default {
  name: 'TableResults',
  props: {
    table: { type: Object, default: () => {} },
    enableSwitches: { type: Boolean, default: false },
  },
};
</script>

<style lang="scss" scoped>
.result-entry:not(:last-child) {
  border-bottom: 1px solid lightgray;
}
</style>
