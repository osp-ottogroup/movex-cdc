<template>
  <div class="container">
    <b-collapse
      class="card"
      v-for="(result, index) of deploymentResults"
      :key="index">
      <template #trigger="props">
        <div class="card-header" role="button">
          <div class="card-header-title is-justify-content-space-between">
            <b-field grouped>
              <b-field label="Schema" custom-class="is-size-7">
                {{result.schemaName}}
              </b-field>
              <b-field v-if="enableSwitches">
                <template #label>
                  <div class="is-size-7 has-text-grey" @click.stop>
                    Deploy
                    <b-tooltip label="Select all pending trigger changes for deployment.Then click the button 'Deploy' to execute the changes."
                               multilined="true">
                      <a @click="onSelectAll(result)">All</a>
                    </b-tooltip>
                    |
                    <b-tooltip label="Unmark all pending trigger changes from deployment.">
                      <a @click="onDeselectAll(result)">No</a>
                    </b-tooltip>
                    tables
                  </div>
                </template>
              </b-field>
            </b-field>
            <div>
              <label class="label is-size-7">{{tableMessage(result)}}</label>
              <label v-if="result.errorCount > 0" class="label is-size-7 has-text-danger">{{errorsMessage(result)}}</label>
            </div>
          </div>
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
  methods: {
    tableMessage(schema) {
      const count = schema.tables.length;
      return count === 1 ? `${count} Table` : `${count} Tables`;
    },
    errorsMessage(schema) {
      const count = schema.errorCount;
      return count === 1 ? `${count} error exists` : `${count} errors exists`;
    },
    onSelectAll(schema) {
      schema.tables.forEach((table) => {
        // eslint-disable-next-line no-param-reassign
        table.deploy = true;
      });
    },
    onDeselectAll(schema) {
      schema.tables.forEach((table) => {
        // eslint-disable-next-line no-param-reassign
        table.deploy = false;
      });
    },
  },
};
</script>
