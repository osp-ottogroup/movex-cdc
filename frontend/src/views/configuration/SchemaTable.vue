<template>
  <div>
    <b-table ref="table"
             :data="schemas"
             :columns="columns"
             detailed
             detail-key="id"
             :selected="currentSchema"
             :show-detail-icon="false"
             @click="setCurrentSchema">
      <template slot="detail" slot-scope="props">
        <b-field label="Topic" label-position="on-border">
          <b-input placeholder="Enter Topic"
                   v-model="props.row.topic"
                   size="is-small"
                   :icon-right="props.row.topicChanged ? 'save' : ''"
                   :icon-right-clickable="props.row.topicChanged"
                   @icon-right-click="onSaveSchema(props.row)"
                   @input="onTopicChanged(props.row)">
          </b-input>
        </b-field>
      </template>
    </b-table>
  </div>
</template>

<script>
import CRUDService from '@/services/CRUDService';

export default {
  name: 'SchemaTable',
  props: {
    schemas: { type: Array, default: () => [] },
  },
  data() {
    return {
      currentSchema: null,
      columns: [
        { field: 'name', label: 'Schemas' },
      ],
    };
  },
  methods: {
    setCurrentSchema(schema) {
      if (this.currentSchema !== null) {
        this.$refs.table.toggleDetails(this.currentSchema);
      }
      this.currentSchema = schema;
      this.$refs.table.toggleDetails(schema);
      this.$emit('schema-selected', schema);
    },
    async onSaveSchema(schema) {
      try {
        await CRUDService.schemas.update(schema.id, { schema });
        // eslint-disable-next-line no-param-reassign
        schema.topicChanged = false;
        this.$buefy.toast.open({
          message: `Saved changes to schema '${schema.name}'!`,
          type: 'is-success',
        });
      } catch (e) {
        this.$buefy.toast.open({
          message: 'An error occurred!',
          type: 'is-danger',
          duration: 5000,
        });
      }
    },
    onTopicChanged(schema) {
      if (!schema.topicChanged) {
        this.$set(schema, 'topicChanged', true);
      }
    },
  },
};
</script>
