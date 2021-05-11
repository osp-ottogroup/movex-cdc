<template>
  <div class="container">
    <b-collapse
      class="card"
      v-for="(result, index) of deploymentResults"
      :key="index">
      <template #trigger="props">
        <div class="card-header" role="button">
          <p class="card-header-title">
            <b-field label="Schema" custom-class="is-size-7">
              {{result.schemaName}}
            </b-field>
          </p>
          <a class="card-header-icon">
            <b-icon
              :icon="props.open ? 'menu-down' : 'menu-up'">
            </b-icon>
          </a>
        </div>
      </template>
      <div class="card-content p-0 pl-6">
        <TableResults v-for="(table, index) in result.tables"
                      :key="index"
                      :table="table"
                      :enableSwitches="enableSwitches"
                      @tableSelected="$emit('tableSelected', table)"
                      @tableDeselected="$emit('tableDeselected', table)"
        />
      </div>
    </b-collapse>
  </div>
</template>

<script>
import TableResults from '@/views/deployment/TableResults.vue';

export default {
  name: 'DeploymentResults',
  components: {
    TableResults,
  },
  props: {
    deploymentResults: { type: Array, default: () => [] },
    enableSwitches: { type: Boolean, default: false },
  },
};
</script>
